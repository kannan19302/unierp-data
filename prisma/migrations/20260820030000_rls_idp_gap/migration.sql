-- Pre-existing RLS gap, discovered (not introduced) while verifying the
-- P1 devplatform migration with check-rls-verify.mjs: four IDP tables carry
-- a tenant column but shipped with RLS never enabled. Same class of defect
-- 20260819000000_rls_for_untracked_tables fixed for 18 core tables — these
-- four live in prisma/idp-schema.prisma (same Postgres database, same
-- prisma/migrations history, separate schema file) and were missed by that
-- pass because check-rls-verify.mjs did not scan the IDP schema until this
-- run's version of the script.
--
-- Severity: these are OAuth authorization codes, refresh token hashes,
-- client consent grants and platform authorization grants — the tables that
-- decide who gets a token for which tenant. A cross-tenant read here is a
-- cross-tenant auth bypass, not merely a data leak.

ALTER TABLE "oauth_authorization_codes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "oauth_authorization_codes" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_oauth_authorization_codes" ON "oauth_authorization_codes";
CREATE POLICY "tenant_isolation_oauth_authorization_codes" ON "oauth_authorization_codes"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "oauth_refresh_grants" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "oauth_refresh_grants" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_oauth_refresh_grants" ON "oauth_refresh_grants";
CREATE POLICY "tenant_isolation_oauth_refresh_grants" ON "oauth_refresh_grants"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "oauth_client_consents" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "oauth_client_consents" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_oauth_client_consents" ON "oauth_client_consents";
CREATE POLICY "tenant_isolation_oauth_client_consents" ON "oauth_client_consents"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

-- PlatformGrant.tenantId is NULLABLE by design (see the model's own doc
-- comment): a ROLE- or PLAN-scoped grant applies to every tenant and
-- legitimately has no tenant_id at all. The standard
-- `tenant_id = current_tenant_id()` predicate would hide every such row from
-- every tenant session — not a security fix, a functional break (nobody
-- could authorize against a role- or plan-wide grant again). The policy
-- below admits a row if it is untargeted (global) OR targeted at the calling
-- tenant, which is the actual access rule this table already encodes in its
-- nullability.
ALTER TABLE "platform_grants" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "platform_grants" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_platform_grants" ON "platform_grants";
CREATE POLICY "tenant_isolation_platform_grants" ON "platform_grants"
    USING ("tenant_id" IS NULL OR "tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" IS NULL OR "tenant_id" = current_tenant_id());
