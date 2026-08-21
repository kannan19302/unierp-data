-- Plan phase P1 — DevProject, the unified id space for Apps (BuilderModule)
-- and Sites (WebSite). See prisma/schema/developer-platform.prisma for the
-- design rationale. Pure expand: two new tables, two new back-relation FKs
-- via unique columns on existing tables. Nothing here is destructive and
-- nothing here is required by any existing code path yet.
--
-- Hand-written rather than `prisma migrate dev`-generated: this database's
-- migration history has a pre-existing shadow-DB replay failure unrelated to
-- this change (20260819000000_rls_for_untracked_tables fails to replay
-- cleanly from empty — a table ordering issue in migration history, not a
-- schema drift `prisma migrate diff` would catch against the live DB).
-- Matches the shape of 20260818020000_w9_support_impersonation, the most
-- recent migration written the same way for the same reason.

CREATE TABLE "dev_projects" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "description" TEXT,
    "icon" TEXT,
    "color" TEXT,
    "status" TEXT NOT NULL DEFAULT 'DRAFT',
    "app_id" TEXT,
    "site_id" TEXT,
    "archived_at" TIMESTAMP(3),
    "created_by" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "dev_projects_pkey" PRIMARY KEY ("id")
);

-- Prisma cannot express "exactly one of these two columns is set" as a
-- schema-level constraint, so it is hand-written here rather than derived.
ALTER TABLE "dev_projects" ADD CONSTRAINT "dev_projects_kind_target_xor"
    CHECK (
        ("kind" = 'APP'  AND "app_id"  IS NOT NULL AND "site_id" IS NULL) OR
        ("kind" = 'SITE' AND "site_id" IS NOT NULL AND "app_id"  IS NULL)
    );

CREATE UNIQUE INDEX "dev_projects_app_id_key" ON "dev_projects" ("app_id");
CREATE UNIQUE INDEX "dev_projects_site_id_key" ON "dev_projects" ("site_id");
CREATE UNIQUE INDEX "dev_projects_tenant_id_kind_slug_key" ON "dev_projects" ("tenant_id", "kind", "slug");
CREATE INDEX "dev_projects_tenant_id_kind_status_idx" ON "dev_projects" ("tenant_id", "kind", "status");
CREATE INDEX "dev_projects_tenant_id_updated_at_idx" ON "dev_projects" ("tenant_id", "updated_at");

ALTER TABLE "dev_projects" ADD CONSTRAINT "dev_projects_app_id_fkey"
    FOREIGN KEY ("app_id") REFERENCES "builder_modules"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "dev_projects" ADD CONSTRAINT "dev_projects_site_id_fkey"
    FOREIGN KEY ("site_id") REFERENCES "web_sites"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "dev_project_recents" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "project_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "last_opened_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "open_count" INTEGER NOT NULL DEFAULT 1,
    CONSTRAINT "dev_project_recents_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "dev_project_recents_user_id_project_id_key" ON "dev_project_recents" ("user_id", "project_id");
CREATE INDEX "dev_project_recents_tenant_id_user_id_last_opened_at_idx" ON "dev_project_recents" ("tenant_id", "user_id", "last_opened_at" DESC);

ALTER TABLE "dev_project_recents" ADD CONSTRAINT "dev_project_recents_project_id_fkey"
    FOREIGN KEY ("project_id") REFERENCES "dev_projects"("id") ON DELETE CASCADE ON UPDATE CASCADE;
