-- Plan phase P3 — the artifact ownership plane. See
-- prisma/schema/developer-platform.prisma for why `artifact_id` is not a
-- foreign key and why the display columns are denormalised.
--
-- Pure expand: two new tables, no changes to any existing one. Nothing reads
-- these yet; the backfill and the service that maintains them land
-- separately so this can be applied and rolled back on its own.

CREATE TABLE "builder_artifacts" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "artifact_type" TEXT NOT NULL,
    "artifact_id" TEXT NOT NULL,
    "owner_project_id" TEXT,
    "name" TEXT NOT NULL,
    "slug" TEXT,
    "status" TEXT NOT NULL DEFAULT 'DRAFT',
    "icon" TEXT,
    "created_by" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "deleted_at" TIMESTAMP(3),
    CONSTRAINT "builder_artifacts_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "builder_artifacts_tenant_id_artifact_type_artifact_id_key"
    ON "builder_artifacts" ("tenant_id", "artifact_type", "artifact_id");
CREATE INDEX "builder_artifacts_tenant_id_owner_project_id_artifact_type_idx"
    ON "builder_artifacts" ("tenant_id", "owner_project_id", "artifact_type");
CREATE INDEX "builder_artifacts_tenant_id_artifact_type_updated_at_idx"
    ON "builder_artifacts" ("tenant_id", "artifact_type", "updated_at" DESC);

-- SET NULL, not CASCADE: deleting a project must return its artifacts to the
-- Library, never destroy them. A form authored inside an app that is later
-- deleted is still a form the tenant made.
ALTER TABLE "builder_artifacts" ADD CONSTRAINT "builder_artifacts_owner_project_id_fkey"
    FOREIGN KEY ("owner_project_id") REFERENCES "dev_projects"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE "builder_artifact_attachments" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "artifact_id" TEXT NOT NULL,
    "project_id" TEXT NOT NULL,
    "is_owner" BOOLEAN NOT NULL DEFAULT false,
    "pinned_release_id" TEXT,
    "attached_by" TEXT,
    "attached_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "detached_at" TIMESTAMP(3),
    CONSTRAINT "builder_artifact_attachments_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "builder_artifact_attachments_artifact_id_project_id_key"
    ON "builder_artifact_attachments" ("artifact_id", "project_id");
CREATE INDEX "builder_artifact_attachments_tenant_id_project_id_idx"
    ON "builder_artifact_attachments" ("tenant_id", "project_id");

ALTER TABLE "builder_artifact_attachments" ADD CONSTRAINT "builder_artifact_attachments_artifact_id_fkey"
    FOREIGN KEY ("artifact_id") REFERENCES "builder_artifacts"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "builder_artifact_attachments" ADD CONSTRAINT "builder_artifact_attachments_project_id_fkey"
    FOREIGN KEY ("project_id") REFERENCES "dev_projects"("id") ON DELETE CASCADE ON UPDATE CASCADE;
