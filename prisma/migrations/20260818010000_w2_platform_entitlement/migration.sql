-- W2 - platform entitlement, third-party scopes, and agent delegation.
--
-- W1 built the mechanism that issues tokens; nothing yet says WHICH of the ten
-- platforms a given token may be issued for beyond the one hardcoded rule in
-- PlatformAccessPolicy (INTERNAL platforms require control-plane authority).
-- This migration makes that a database concept, so "Web Studio Pro unlocks P5"
-- becomes a row an operator edits from Provider Admin OS rather than a code
-- change and a deploy.
--
-- == Platform catalog ========================================================
CREATE TABLE "platforms" (
    "code"            TEXT NOT NULL,
    "name"            TEXT NOT NULL,
    "port"            INTEGER NOT NULL,
    "base_url"        TEXT NOT NULL,
    "icon"            TEXT,
    -- INTERNAL: UniERP staff only (P2). PUBLIC: reachable by tenant users and
    -- developers subject to entitlement (P1, P3-P10).
    "audience"        TEXT NOT NULL DEFAULT 'PUBLIC',
    "requires_tenant" BOOLEAN NOT NULL DEFAULT true,
    "created_at"      TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at"      TIMESTAMP(3) NOT NULL,

    CONSTRAINT "platforms_pkey" PRIMARY KEY ("code")
);
ALTER TABLE "platforms" ADD CONSTRAINT "platforms_audience_check"
    CHECK ("audience" IN ('INTERNAL', 'PUBLIC'));

-- == Entitlement grants =======================================================
-- Three ways a platform becomes reachable, checked independently at
-- /oidc/authorize (any one match admits):
--
--   ROLE  a named role may always enter (e.g. UniERP staff roles -> P2)
--   PLAN  a tenant's SaaSPlan unlocks a platform for every user in that tenant
--         (e.g. the plan whose SaaSPlanFeature has featureKey='web_studio' -> P5)
--   USER  a specific user is granted individually (support overrides, pilots)
--
-- tenant_id scopes a USER or PLAN grant to one tenant; null means "applies to
-- any tenant matching the subject" (a ROLE grant is normally global).
CREATE TABLE "platform_grants" (
    "id"             TEXT NOT NULL,
    "subject_type"   TEXT NOT NULL,
    -- ROLE: a role name.  PLAN: a SaaSPlan.id.  USER: a User.id.
    "subject_id"     TEXT NOT NULL,
    "platform_code"  TEXT NOT NULL,
    "tenant_id"      TEXT,
    "created_at"     TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "platform_grants_pkey" PRIMARY KEY ("id")
);
ALTER TABLE "platform_grants" ADD CONSTRAINT "platform_grants_subject_type_check"
    CHECK ("subject_type" IN ('ROLE', 'PLAN', 'USER'));
-- A USER grant not scoped to a tenant is meaningless: which tenant would the
-- resulting token be issued for? Only ROLE and PLAN may be tenant-agnostic.
ALTER TABLE "platform_grants" ADD CONSTRAINT "platform_grants_user_requires_tenant"
    CHECK ("subject_type" != 'USER' OR "tenant_id" IS NOT NULL);

CREATE UNIQUE INDEX "platform_grants_unique_grant"
    ON "platform_grants" ("subject_type", "subject_id", "platform_code", COALESCE("tenant_id", ''));
CREATE INDEX "platform_grants_platform_code_idx" ON "platform_grants" ("platform_code");
CREATE INDEX "platform_grants_tenant_id_idx" ON "platform_grants" ("tenant_id");

ALTER TABLE "platform_grants"
    ADD CONSTRAINT "platform_grants_platform_code_fkey" FOREIGN KEY ("platform_code")
    REFERENCES "platforms"("code") ON DELETE CASCADE ON UPDATE CASCADE;

-- These are authorization-server catalog/policy tables, in the same category
-- as oauth_clients from W1 and for the same reason: RLS would make platform
-- entitlement invisible to the one anonymous-until-authenticated request that
-- needs it (/oidc/authorize, before a tenant session exists). No tenant policy.

-- == Agent principals (RFC 8693 token exchange) ==============================
-- An agent is never authenticated with its own credentials. It exists only as
-- something a live user token can be exchanged for, and its authority is
-- capped at exchange time to a SUBSET of what that user already holds -
-- enforced in application code (AgentDelegationService), not just declared
-- here. This table is the tenant's registry of which agents may be exchanged
-- for at all, and with what ceiling.
CREATE TABLE "agent_definitions" (
    "id"                   TEXT NOT NULL,
    "tenant_id"            TEXT NOT NULL,
    "name"                 TEXT NOT NULL,
    "description"          TEXT,
    -- The upper bound on delegated authority. Still intersected with the
    -- delegating user's own permissions at every exchange - this is a ceiling,
    -- not a grant.
    "allowed_permissions"  TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    -- Actions at/above this many permission-checks of "write" severity route
    -- through step-up MFA / two-person control before the agent may proceed,
    -- mirroring the guards api/src/common/guards already enforces for humans.
    "requires_confirmation_above" TEXT,
    "status"               TEXT NOT NULL DEFAULT 'ACTIVE',
    "created_at"           TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at"           TIMESTAMP(3) NOT NULL,

    CONSTRAINT "agent_definitions_pkey" PRIMARY KEY ("id")
);
ALTER TABLE "agent_definitions" ADD CONSTRAINT "agent_definitions_status_check"
    CHECK ("status" IN ('ACTIVE', 'DISABLED'));
-- An agent permitted system.* or platform.* would be a backdoor around the
-- control-plane boundary idp/src/modules/oidc/services/platform-access.policy.ts
-- exists to enforce - not just unlikely, structurally impossible.
-- Postgres CHECK constraints cannot contain a subquery (error 0A000), so the
-- unnest()+EXISTS form is expressed as an IMMUTABLE function instead. The
-- function body may use a subquery freely; only the top-level CHECK expression
-- may not.
CREATE OR REPLACE FUNCTION agent_permissions_within_control_plane_bound(perms TEXT[])
RETURNS BOOLEAN AS $$
    SELECT NOT EXISTS (
        SELECT 1 FROM unnest(perms) p
        WHERE p LIKE 'system.%' OR p LIKE 'platform.%' OR p = '*'
    );
$$ LANGUAGE sql IMMUTABLE;

ALTER TABLE "agent_definitions" ADD CONSTRAINT "agent_definitions_no_control_plane"
    CHECK (agent_permissions_within_control_plane_bound("allowed_permissions"));

CREATE UNIQUE INDEX "agent_definitions_tenant_id_name_key" ON "agent_definitions" ("tenant_id", "name");
CREATE INDEX "agent_definitions_tenant_id_idx" ON "agent_definitions" ("tenant_id");

ALTER TABLE "agent_definitions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "agent_definitions" FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation_agent_definitions" ON "agent_definitions"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

-- == Agent audit trail =========================================================
-- Every token-exchange grant, so "who created this invoice" always answers
-- both the human (sub) and the agent (act) - the point of the `act` claim
-- introduced on access tokens in W1's OidcTokenService.
CREATE TABLE "agent_delegations" (
    "id"              TEXT NOT NULL,
    "tenant_id"       TEXT NOT NULL,
    "agent_id"        TEXT NOT NULL,
    "delegating_user_id" TEXT NOT NULL,
    -- The actual permission set granted THIS exchange: allowed_permissions
    -- intersected with the user's permissions at that moment. Recorded because
    -- the ceiling and the user's permissions both change over time; the audit
    -- trail must reflect what authority existed when the action happened, not
    -- what the ceiling says today.
    "effective_permissions" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "sid"             TEXT NOT NULL,
    "expires_at"      TIMESTAMP(3) NOT NULL,
    "created_at"      TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "agent_delegations_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "agent_delegations_tenant_id_idx" ON "agent_delegations" ("tenant_id");
CREATE INDEX "agent_delegations_agent_id_idx" ON "agent_delegations" ("agent_id");
CREATE INDEX "agent_delegations_sid_idx" ON "agent_delegations" ("sid");

ALTER TABLE "agent_delegations"
    ADD CONSTRAINT "agent_delegations_agent_id_fkey" FOREIGN KEY ("agent_id")
    REFERENCES "agent_definitions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "agent_delegations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "agent_delegations" FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation_agent_delegations" ON "agent_delegations"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());
