-- Plan phase P1 backfill — one DevProject per existing BuilderModule (kind
-- APP) and WebSite (kind SITE). Pure data, idempotent via ON CONFLICT on the
-- unique app_id/site_id indexes so re-running this migration (or a future
-- reconciler sweep using the same statements) is a no-op for rows already
-- backfilled.
--
-- Runs as the migration role, which reads across every tenant in one
-- INSERT...SELECT — necessary for a one-time backfill, and safe: the row
-- written for each source record still carries THAT record's own tenant_id,
-- so RLS on dev_projects itself is fully intact for every subsequent read.
--
-- gen_random_uuid() (built into Postgres 13+, no extension needed) rather
-- than matching Prisma's client-side cuid() — this is the one place ids are
-- minted outside the Prisma client, and an opaque unique id is all that's
-- required; every id minted after this migration goes through cuid() as
-- normal application writes do.

INSERT INTO "dev_projects" (
    "id", "tenant_id", "kind", "name", "slug", "description", "icon", "color",
    "status", "app_id", "created_by", "created_at", "updated_at"
)
SELECT
    gen_random_uuid()::text, "tenant_id", 'APP', "name", "slug", "description",
    "icon", "color", "status", "id", "created_by", "created_at", now()
FROM "builder_modules"
ON CONFLICT ("app_id") DO NOTHING;

INSERT INTO "dev_projects" (
    "id", "tenant_id", "kind", "name", "slug", "status", "site_id",
    "created_by", "created_at", "updated_at"
)
SELECT
    gen_random_uuid()::text, "tenant_id", 'SITE', "name", "slug", "status",
    "id", "created_by", "created_at", now()
FROM "web_sites"
ON CONFLICT ("site_id") DO NOTHING;
