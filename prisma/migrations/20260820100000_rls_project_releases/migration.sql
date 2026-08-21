-- RLS for project_releases (P6). Required in the same PR by
-- check-rls-verify.mjs. Standard tenant predicate: this table is only ever
-- reached by authenticated, tenant-scoped requests, so unlike the IdP OAuth
-- tables there is no pre-authentication path to accommodate.

ALTER TABLE "project_releases" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "project_releases" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_project_releases" ON "project_releases";
CREATE POLICY "tenant_isolation_project_releases" ON "project_releases"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());
