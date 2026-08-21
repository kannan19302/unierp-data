-- Plan phase P8, second attempt — the contract migration. DESTRUCTIVE.
--
-- The first attempt (20260820140000) was reverted by 20260820150000 because
-- rebuilding produced 86 compile errors across the legacy builder services:
-- every one a read of a column or table this drops. That was the "zero legacy
-- reads" gate doing exactly its job.
--
-- What changed since, and why this attempt is safe:
--   * 20260820170000 / 20260820190000 promoted `pages` and `dataModels` out
--     of JSON into `builder_module_pages` / `builder_module_data_models`
--     (including the `layout` array, which the first pass would have lost).
--   * `components` was already superseded by `builder_artifacts` (P3).
--   * `ModuleCompositionService` now serves all three to the legacy services
--     in their original array shapes, so `/api/v1/builder/modules/:id/*`
--     responses are byte-compatible while the storage moved underneath.
--   * builder.service, builder-stats, builder-governance, builder-web-content
--     and builder-enterprise were rewritten to read the new sources. The api
--     image builds clean, and the legacy routes were round-trip verified
--     (add page/component/dataModel -> read back identical shapes).
--
-- Archives from the first attempt already exist (`*_archive_p8`) and are NOT
-- recreated, so they still hold the pre-contract snapshot. Drop them in a
-- later, separate migration once a release has passed.

-- ── 1. builder_modules JSON columns ──
CREATE TABLE IF NOT EXISTS "builder_modules_json_archive_p8_v2" AS
  SELECT id, tenant_id, components, pages, "dataModels", now() AS archived_at
    FROM "builder_modules";

ALTER TABLE "builder_modules" DROP COLUMN IF EXISTS "components";
ALTER TABLE "builder_modules" DROP COLUMN IF EXISTS "pages";
ALTER TABLE "builder_modules" DROP COLUMN IF EXISTS "dataModels";

-- ── 2. app_releases -> project_releases ──
DO $$
DECLARE orphaned bigint;
BEGIN
  SELECT count(*) INTO orphaned
    FROM "app_releases" ar
   WHERE NOT EXISTS (SELECT 1 FROM "project_releases" pr WHERE pr.id = ar.id);
  IF orphaned > 0 THEN
    RAISE EXCEPTION
      'P8: % app_releases row(s) have no project_releases counterpart. Re-run the P6 backfill before contracting.', orphaned;
  END IF;
END $$;
DROP TABLE IF EXISTS "app_releases";

-- ── 3. web_pages -> web_site_pages ──
DO $$
DECLARE unmigrated bigint;
BEGIN
  SELECT count(*) INTO unmigrated
    FROM "web_pages" wp
   WHERE NOT EXISTS (SELECT 1 FROM "web_site_pages" sp WHERE sp.id = wp.id);
  IF unmigrated > 0 THEN
    RAISE EXCEPTION
      'P8: % web_pages row(s) were never migrated (see web_page_migration_conflicts). Resolve them before contracting.', unmigrated;
  END IF;
END $$;
DROP TABLE IF EXISTS "web_pages";

-- ── 4. builder_deployments / builder_environments, folded in P6 ──
DROP TABLE IF EXISTS "builder_deployments";
DROP TABLE IF EXISTS "builder_environments";

-- ── 5. deployments.dep_environment_id, the workaround column ──
ALTER TABLE "deployments" DROP CONSTRAINT IF EXISTS "deployments_dep_environment_id_fkey";
ALTER TABLE "deployments" DROP COLUMN IF EXISTS "dep_environment_id";
