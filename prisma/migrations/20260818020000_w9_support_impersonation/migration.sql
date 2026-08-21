-- W9 — consent-gated support impersonation.
--
-- `TenantConsent` and `ImpersonationSession` have existed in
-- prisma/schema/core-part-10.prisma for some time, but NO migration ever
-- created their tables. Everything that read them therefore failed at
-- runtime against a real database:
--
--   * api/src/modules/admin/platform.service.ts's grantSupportConsent() and
--     getSupportSessions() (pre-existing), and
--   * api/src/modules/admin/support-impersonation.service.ts (added in W9,
--     which is what surfaced this).
--
-- A model in the schema with no migration typechecks perfectly and generates
-- a working Prisma client, so nothing catches it until a query runs. This
-- migration closes the gap; the shape below matches those two models exactly,
-- so `prisma migrate diff` stays empty afterwards.

CREATE TABLE "tenant_consents" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "granted_by" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'ACTIVE',
    "expires_at" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "tenant_consents_pkey" PRIMARY KEY ("id")
);
ALTER TABLE "tenant_consents" ADD CONSTRAINT "tenant_consents_status_check"
    CHECK ("status" IN ('ACTIVE', 'REVOKED', 'EXPIRED'));
CREATE INDEX "tenant_consents_tenant_id_idx" ON "tenant_consents" ("tenant_id");
CREATE INDEX "tenant_consents_status_idx" ON "tenant_consents" ("status");

CREATE TABLE "impersonation_sessions" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "impersonator_id" TEXT NOT NULL,
    "target_user_id" TEXT NOT NULL,
    "consent_id" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'ACTIVE',
    "expires_at" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "impersonation_sessions_pkey" PRIMARY KEY ("id")
);
ALTER TABLE "impersonation_sessions" ADD CONSTRAINT "impersonation_sessions_status_check"
    CHECK ("status" IN ('ACTIVE', 'EXPIRED'));
CREATE INDEX "impersonation_sessions_tenant_id_idx" ON "impersonation_sessions" ("tenant_id");
CREATE INDEX "impersonation_sessions_impersonator_id_idx" ON "impersonation_sessions" ("impersonator_id");

-- Tenant isolation, same ENABLE + FORCE + current_tenant_id() shape every
-- other tenant-scoped table uses. Deliberately applied even though support
-- impersonation is initiated by provider staff: the ROWS belong to a tenant,
-- and a support operator holding a session for tenant A must not be able to
-- read tenant B's impersonation history as a side effect.
ALTER TABLE "tenant_consents" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tenant_consents" FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation_tenant_consents" ON "tenant_consents"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "impersonation_sessions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "impersonation_sessions" FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation_impersonation_sessions" ON "impersonation_sessions"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

-- The one genuinely cross-tenant read: "which support sessions are live right
-- now, across the whole estate". FORCE RLS makes that impossible from the
-- application role by design, so it goes through a SECURITY DEFINER function
-- — the same audited-exception pattern auth_lookup_oauth_identity() uses for
-- its own pre-tenant-context lookup (20260719060000_oauth_identities).
--
-- Access to this function is NOT what authorizes the caller; the controller
-- gates it behind ControlPlaneGuard plus the platform.support.l2 permission.
-- This only removes the RLS barrier for a query that is legitimately estate-wide.
CREATE OR REPLACE FUNCTION support_list_active_impersonations()
RETURNS TABLE(
    id TEXT,
    tenant_id TEXT,
    impersonator_id TEXT,
    target_user_id TEXT,
    consent_id TEXT,
    status TEXT,
    expires_at TIMESTAMP(3),
    created_at TIMESTAMP(3)
)
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
STABLE
AS $$
    SELECT s.id, s.tenant_id, s.impersonator_id, s.target_user_id,
           s.consent_id, s.status, s.expires_at, s.created_at
    FROM impersonation_sessions s
    WHERE s.status = 'ACTIVE' AND s.expires_at > NOW()
    ORDER BY s.created_at DESC;
$$;

REVOKE ALL ON FUNCTION support_list_active_impersonations() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION support_list_active_impersonations() TO unerp_api;
