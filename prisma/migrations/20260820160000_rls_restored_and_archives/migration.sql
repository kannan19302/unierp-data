-- Restores RLS on tables that lost it, and adds it to tables that never had it.
--
-- TWO distinct gaps, both mine:
--
-- 1. `20260820150000_p8_revert` restored app_releases / web_pages /
--    builder_deployments / builder_environments with
--    `CREATE TABLE ... AS SELECT`, which copies rows and NOTHING else — no
--    primary key, no indexes, and critically no row-level security. The
--    tables came back with their tenant_id column and no isolation at all.
--    check-rls-verify.mjs caught it immediately, which is exactly its job.
--
-- 2. The `_archive_p8` tables (and `web_page_migration_conflicts` from P7)
--    are new tables carrying tenant_id that were never enrolled. An archive
--    of tenant data is still tenant data: leaving it unprotected would mean
--    the contract migration quietly created a cross-tenant readable copy of
--    everything it removed.
--
-- Standard tenant predicate throughout — all of these are reached only by
-- authenticated, tenant-scoped requests.

ALTER TABLE "app_releases" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "app_releases" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_app_releases" ON "app_releases";
CREATE POLICY "tenant_isolation_app_releases" ON "app_releases"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "builder_deployments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "builder_deployments" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_builder_deployments" ON "builder_deployments";
CREATE POLICY "tenant_isolation_builder_deployments" ON "builder_deployments"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "builder_environments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "builder_environments" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_builder_environments" ON "builder_environments";
CREATE POLICY "tenant_isolation_builder_environments" ON "builder_environments"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "web_pages" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "web_pages" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_web_pages" ON "web_pages";
CREATE POLICY "tenant_isolation_web_pages" ON "web_pages"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "app_releases_archive_p8" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "app_releases_archive_p8" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_app_releases_archive_p8" ON "app_releases_archive_p8";
CREATE POLICY "tenant_isolation_app_releases_archive_p8" ON "app_releases_archive_p8"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "builder_deployments_archive_p8" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "builder_deployments_archive_p8" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_builder_deployments_archive_p8" ON "builder_deployments_archive_p8";
CREATE POLICY "tenant_isolation_builder_deployments_archive_p8" ON "builder_deployments_archive_p8"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "builder_environments_archive_p8" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "builder_environments_archive_p8" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_builder_environments_archive_p8" ON "builder_environments_archive_p8";
CREATE POLICY "tenant_isolation_builder_environments_archive_p8" ON "builder_environments_archive_p8"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "builder_modules_json_archive_p8" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "builder_modules_json_archive_p8" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_builder_modules_json_archive_p8" ON "builder_modules_json_archive_p8";
CREATE POLICY "tenant_isolation_builder_modules_json_archive_p8" ON "builder_modules_json_archive_p8"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "web_pages_archive_p8" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "web_pages_archive_p8" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_web_pages_archive_p8" ON "web_pages_archive_p8";
CREATE POLICY "tenant_isolation_web_pages_archive_p8" ON "web_pages_archive_p8"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "web_page_migration_conflicts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "web_page_migration_conflicts" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_web_page_migration_conflicts" ON "web_page_migration_conflicts";
CREATE POLICY "tenant_isolation_web_page_migration_conflicts" ON "web_page_migration_conflicts"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());
