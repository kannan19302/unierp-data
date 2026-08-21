-- Plan phase P6 — ProjectRelease, and the Deployment.environment_id FK fix.
--
-- ── Part 1: project_releases ──
-- Supersedes app_releases (App-only, hung off builder_modules) with a model
-- that can version a Site too, because DevProject is one id space over both.
--
-- The backfill PRESERVES app_releases.id. That is deliberate and load-bearing:
-- `installed_apps.release_id` already stores app_releases ids, so copying the
-- ids across means those references keep resolving with no rewrite, and the
-- step is trivially reversible.

CREATE TABLE "project_releases" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "project_id" TEXT NOT NULL,
    "version" TEXT NOT NULL,
    "channel" TEXT NOT NULL DEFAULT 'ORGANIZATION',
    "release_type" TEXT NOT NULL DEFAULT 'STANDARD',
    "changelog" TEXT,
    "snapshot" JSONB NOT NULL DEFAULT '{}',
    "schema_version" INTEGER NOT NULL DEFAULT 1,
    "test_score" INTEGER,
    "status" TEXT NOT NULL DEFAULT 'DRAFT',
    "published_by" TEXT,
    "published_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "project_releases_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "project_releases_project_id_version_key"
    ON "project_releases" ("project_id", "version");
CREATE INDEX "project_releases_tenant_id_project_id_published_at_idx"
    ON "project_releases" ("tenant_id", "project_id", "published_at" DESC);
CREATE INDEX "project_releases_channel_status_idx"
    ON "project_releases" ("channel", "status");

ALTER TABLE "project_releases" ADD CONSTRAINT "project_releases_project_id_fkey"
    FOREIGN KEY ("project_id") REFERENCES "dev_projects"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Backfill from app_releases, id-preserving. Idempotent.
-- Only releases whose module already has a DevProject can be carried over;
-- the P1 backfill created one per builder_modules row, so in practice that is
-- all of them. Any that somehow lack one are left behind rather than given a
-- fabricated parent, and will show up as a count mismatch.
INSERT INTO "project_releases"
  (id, tenant_id, project_id, version, channel, changelog, snapshot, test_score, status, published_by, published_at, created_at)
SELECT r.id, r.tenant_id, p.id, r.version, r.channel, r.changelog, r.snapshot,
       r.test_score, r.status, r.published_by, r.published_at, r.published_at
FROM "app_releases" r
JOIN "dev_projects" p ON p.app_id = r.module_id
ON CONFLICT (id) DO NOTHING;

-- ── Part 2: the deployments.environment_id FK fix ──
--
-- `environment_id` was declared as a FK to `deployment_stages`, so
-- `deployment.environment` returned a stage. A second, correct
-- `dep_environment_id -> environments` sat unused beside it.
--
-- The swap is done as add → backfill → swap, NOT as an in-place FK
-- re-point. An ALTER of the existing constraint would assert that every
-- current value is an `environments.id`, and there is no way to tell from
-- the data which rows were written against which relation — so any row that
-- really did hold a stage id would fail the constraint mid-migration, or
-- worse, silently point at an unrelated environment that happens to share
-- the id. Moving values explicitly, from the column that is known-correct,
-- is the only safe order.
--
-- `dep_environment_id` is KEPT here (deprecated) so a reader mid-deploy does
-- not break; it is dropped in the P8 contract migration.

ALTER TABLE "deployments" ADD COLUMN "environment_id_new" TEXT;

-- Prefer the known-correct column. Rows with neither are left NULL and are
-- reported by the guard below rather than being guessed at.
UPDATE "deployments" SET "environment_id_new" = "dep_environment_id"
 WHERE "dep_environment_id" IS NOT NULL;

-- A row whose environment_id already names a real environment is carried
-- over too; one that names a deployment_stage is NOT, because that value is
-- meaningless in the new relation.
UPDATE "deployments" d SET "environment_id_new" = d."environment_id"
 WHERE d."environment_id_new" IS NULL
   AND EXISTS (SELECT 1 FROM "environments" e WHERE e.id = d."environment_id");

-- Fail loudly rather than drop deployments on the floor. If this fires, the
-- rows genuinely cannot be mapped and need a human decision.
DO $$
DECLARE unmapped bigint;
BEGIN
  SELECT count(*) INTO unmapped FROM "deployments" WHERE "environment_id_new" IS NULL;
  IF unmapped > 0 THEN
    RAISE EXCEPTION
      'P6: % deployment row(s) have no resolvable environment. Populate dep_environment_id for them, then re-run.', unmapped;
  END IF;
END $$;

ALTER TABLE "deployments" DROP CONSTRAINT IF EXISTS "deployments_environment_id_fkey";
ALTER TABLE "deployments" DROP COLUMN "environment_id";
ALTER TABLE "deployments" RENAME COLUMN "environment_id_new" TO "environment_id";
ALTER TABLE "deployments" ALTER COLUMN "environment_id" SET NOT NULL;

ALTER TABLE "deployments" ADD CONSTRAINT "deployments_environment_id_fkey"
    FOREIGN KEY ("environment_id") REFERENCES "environments"("id") ON UPDATE CASCADE;

CREATE INDEX IF NOT EXISTS "deployments_tenant_id_environment_id_idx"
    ON "deployments" ("tenant_id", "environment_id");

-- ── Part 3: deployments -> project_releases ──
ALTER TABLE "deployments" ADD COLUMN "release_id" TEXT;
ALTER TABLE "deployments" ADD CONSTRAINT "deployments_release_id_fkey"
    FOREIGN KEY ("release_id") REFERENCES "project_releases"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX "deployments_tenant_id_release_id_idx"
    ON "deployments" ("tenant_id", "release_id");

-- ── Part 4: fold builder_environments / builder_deployments ──
-- `environments` gains the settings column `builder_environments` carried, so
-- the two can be merged rather than coexisting. The old tables are dropped in
-- P8, not here, so this migration stays reversible.
ALTER TABLE "environments" ADD COLUMN IF NOT EXISTS "settings" JSONB NOT NULL DEFAULT '{}';
