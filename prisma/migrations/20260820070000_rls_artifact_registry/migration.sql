-- RLS for the two tables added in 20260820060000_artifact_registry_expand.
-- Required in the same PR by `data/scripts/check-rls-verify.mjs`, which has
-- no exemption list by design.
--
-- The standard `tenant_id = current_tenant_id()` predicate is correct here,
-- unlike the IdP OAuth tables (see 20260820050000): these are only ever
-- touched by authenticated, tenant-scoped requests through `api`, where
-- TenantInterceptor has always established the GUC before the handler runs.
-- There is no pre-authentication access path to weaken the policy for.

ALTER TABLE "builder_artifacts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "builder_artifacts" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_builder_artifacts" ON "builder_artifacts";
CREATE POLICY "tenant_isolation_builder_artifacts" ON "builder_artifacts"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "builder_artifact_attachments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "builder_artifact_attachments" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_builder_artifact_attachments" ON "builder_artifact_attachments";
CREATE POLICY "tenant_isolation_builder_artifact_attachments" ON "builder_artifact_attachments"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());
