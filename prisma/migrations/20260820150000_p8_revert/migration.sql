-- Reverts 20260820140000_p8_contract.
--
-- P8's own gate is "zero legacy reads". Applying it and rebuilding produced
-- 86 compile errors across the legacy builder services:
--   builder.service.ts (55), builder-stats.service.ts (10),
--   builder-governance.service.ts (9), builder-web-content.service.ts (8),
--   builder-enterprise.service.ts (4)
-- — every one of them a read of a column or table the contract dropped. That
-- is not a gate that "mostly" passes; it is the gate failing loudly, which is
-- what it was written to do.
--
-- P8 is therefore blocked on P4's controller split, and the dependency is
-- structural rather than a matter of effort: those services back the
-- `/api/v1/builder/*` routes that the developer-platform frontend still calls
-- for every builder list page (the registry's `listView` components are the
-- legacy pages). Deleting the backend before the frontend is repointed would
-- take the whole UI down; rewriting 86 call sites in code that P4 deletes
-- anyway is churn with real regression risk and no lasting benefit.
--
-- Restoring from the archives P8 deliberately created — which is precisely
-- why it created them. `_archive_p8` tables are left in place; the next
-- attempt can re-run the contract without re-archiving.

-- 1. builder_modules JSON columns
ALTER TABLE "builder_modules" ADD COLUMN IF NOT EXISTS "components" JSONB NOT NULL DEFAULT '[]';
ALTER TABLE "builder_modules" ADD COLUMN IF NOT EXISTS "pages" JSONB NOT NULL DEFAULT '[]';
ALTER TABLE "builder_modules" ADD COLUMN IF NOT EXISTS "dataModels" JSONB NOT NULL DEFAULT '[]';

UPDATE "builder_modules" m
   SET components = a.components, pages = a.pages, "dataModels" = a."dataModels"
  FROM "builder_modules_json_archive_p8" a
 WHERE a.id = m.id;

-- 2. app_releases
CREATE TABLE IF NOT EXISTS "app_releases" AS SELECT * FROM "app_releases_archive_p8";
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'app_releases_pkey') THEN
    ALTER TABLE "app_releases" ADD CONSTRAINT "app_releases_pkey" PRIMARY KEY ("id");
  END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS "app_releases_module_id_version_key" ON "app_releases" ("module_id", "version");
CREATE INDEX IF NOT EXISTS "app_releases_tenant_id_idx" ON "app_releases" ("tenant_id");

-- 3. web_pages
CREATE TABLE IF NOT EXISTS "web_pages" AS SELECT * FROM "web_pages_archive_p8";
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'web_pages_pkey') THEN
    ALTER TABLE "web_pages" ADD CONSTRAINT "web_pages_pkey" PRIMARY KEY ("id");
  END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS "web_pages_tenant_id_slug_key" ON "web_pages" ("tenant_id", "slug");

-- 4. builder_deployments / builder_environments
CREATE TABLE IF NOT EXISTS "builder_environments" AS SELECT * FROM "builder_environments_archive_p8";
CREATE TABLE IF NOT EXISTS "builder_deployments" AS SELECT * FROM "builder_deployments_archive_p8";
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'builder_environments_pkey') THEN
    ALTER TABLE "builder_environments" ADD CONSTRAINT "builder_environments_pkey" PRIMARY KEY ("id");
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'builder_deployments_pkey') THEN
    ALTER TABLE "builder_deployments" ADD CONSTRAINT "builder_deployments_pkey" PRIMARY KEY ("id");
  END IF;
END $$;

-- 5. deployments.dep_environment_id. Restored as a plain nullable column;
-- P6 already moved its values into environment_id, so it is once again the
-- unused duplicate it was before — which is the pre-P8 state this reverts to.
ALTER TABLE "deployments" ADD COLUMN IF NOT EXISTS "dep_environment_id" TEXT;
