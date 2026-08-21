-- RLS for the two tables added in 20260820170000. Required in the same PR
-- by check-rls-verify.mjs.

ALTER TABLE "builder_module_pages" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "builder_module_pages" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_builder_module_pages" ON "builder_module_pages";
CREATE POLICY "tenant_isolation_builder_module_pages" ON "builder_module_pages"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "builder_module_data_models" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "builder_module_data_models" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_builder_module_data_models" ON "builder_module_data_models";
CREATE POLICY "tenant_isolation_builder_module_data_models" ON "builder_module_data_models"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());
