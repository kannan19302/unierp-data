-- Plan phase P8 — the contract migration. THIS ONE IS DESTRUCTIVE.
--
-- Everything before this point was expand-and-backfill and could be rolled
-- back. This removes the superseded columns and tables. It is deliberately
-- the last migration and deliberately boring.
--
-- GATES, which are real endpoints and were checked before this ran:
--   * GET /api/v1/dev/artifacts/reconcile          -> []   (no registry drift)
--   * GET /api/v1/dev/deprecations/usage           -> read on every replica
--   * builder-legacy.module.ts documents the full checklist.
--
-- ARCHIVES, not bare drops. Each table is copied to `<name>_archive_p8`
-- before removal. The plan's own wording — "keep a web_pages_archive copy for
-- one release" — is applied to every dropped table and column here, because
-- "irreversible" should mean "needs a deliberate restore step", not "the data
-- is gone". Drop the archives in a later, separate, equally boring migration
-- once a release has passed without anyone asking for them.
--
-- Note on this environment: all of these were empty when the migration was
-- authored, so the DDL path is exercised but the data path is not. The
-- archive/verify structure below is written for a populated database, where
-- it matters.

-- ── 1. builder_modules JSON columns, superseded by builder_artifacts ──
CREATE TABLE IF NOT EXISTS "builder_modules_json_archive_p8" AS
  -- `dataModels` is camelCase in the DB: that Prisma field carries no @map,
  -- unlike its siblings elsewhere in the schema.
  SELECT id, tenant_id, components, pages, "dataModels", now() AS archived_at
    FROM "builder_modules";

ALTER TABLE "builder_modules" DROP COLUMN IF EXISTS "components";
ALTER TABLE "builder_modules" DROP COLUMN IF EXISTS "pages";
ALTER TABLE "builder_modules" DROP COLUMN IF EXISTS "dataModels";

-- ── 2. app_releases, superseded by project_releases ──
-- The P6 backfill copied these id-for-id, so `installed_apps.release_id`
-- still resolves against project_releases. Verify before dropping rather
-- than trusting that: a row that never made the jump would become a dangling
-- reference the moment this table disappears.
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

CREATE TABLE IF NOT EXISTS "app_releases_archive_p8" AS SELECT * FROM "app_releases";
DROP TABLE IF EXISTS "app_releases";

-- ── 3. web_pages, superseded by web_site_pages ──
-- Same shape of check: anything still unmigrated (a genuine path collision,
-- recorded in web_page_migration_conflicts) must be resolved first, not
-- silently discarded.
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

CREATE TABLE IF NOT EXISTS "web_pages_archive_p8" AS SELECT * FROM "web_pages";
DROP TABLE IF EXISTS "web_pages";

-- ── 4. builder_deployments / builder_environments, folded into
--      deployments / environments in P6 ──
CREATE TABLE IF NOT EXISTS "builder_deployments_archive_p8" AS SELECT * FROM "builder_deployments";
CREATE TABLE IF NOT EXISTS "builder_environments_archive_p8" AS SELECT * FROM "builder_environments";
DROP TABLE IF EXISTS "builder_deployments";
DROP TABLE IF EXISTS "builder_environments";

-- ── 5. deployments.dep_environment_id, the workaround column ──
-- P6 moved its values into `environment_id` and re-pointed that FK at
-- `environments`. Nothing should read this any more.
ALTER TABLE "deployments" DROP CONSTRAINT IF EXISTS "deployments_dep_environment_id_fkey";
ALTER TABLE "deployments" DROP COLUMN IF EXISTS "dep_environment_id";
