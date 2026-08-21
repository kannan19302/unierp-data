-- Row-level security for the two tables added in
-- 20260820010000_devplatform_expand. `data/scripts/check-rls-verify.mjs`
-- derives its expected table set from the Prisma schema on every run and has
-- no exemption list — any model with a `tenantId` field must have RLS,
-- ENABLE + FORCE + a `tenant_isolation_<table>` policy, in the same PR that
-- adds it, or CI fails. Shape matches 20260819000000_rls_for_untracked_tables.

ALTER TABLE "dev_projects" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "dev_projects" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_dev_projects" ON "dev_projects";
CREATE POLICY "tenant_isolation_dev_projects" ON "dev_projects"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "dev_project_recents" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "dev_project_recents" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_dev_project_recents" ON "dev_project_recents";
CREATE POLICY "tenant_isolation_dev_project_recents" ON "dev_project_recents"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());
