-- Developer platform Phase 1 foundation: immutable artifact revisions,
-- typed dependencies, package versions, pinned project installations and
-- consumer-owned overlays. Pure expand: existing builder paths continue to
-- operate while pilot builders move to the canonical revision service.

CREATE TABLE "artifact_revisions" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "artifact_id" TEXT NOT NULL,
  "revision" INTEGER NOT NULL,
  "parent_revision_id" TEXT,
  "api_version" TEXT NOT NULL DEFAULT 'unierp.dev/v1',
  "schema_version" INTEGER NOT NULL DEFAULT 1,
  "source" JSONB NOT NULL,
  "content_hash" TEXT NOT NULL,
  "validation_status" TEXT NOT NULL DEFAULT 'PENDING',
  "validation_result" JSONB,
  "created_by" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "artifact_revisions_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "artifact_revisions_artifact_id_revision_key" ON "artifact_revisions"("artifact_id", "revision");
CREATE UNIQUE INDEX "artifact_revisions_artifact_id_content_hash_key" ON "artifact_revisions"("artifact_id", "content_hash");
CREATE INDEX "artifact_revisions_tenant_id_artifact_id_created_at_idx" ON "artifact_revisions"("tenant_id", "artifact_id", "created_at" DESC);
ALTER TABLE "artifact_revisions" ADD CONSTRAINT "artifact_revisions_artifact_id_fkey" FOREIGN KEY ("artifact_id") REFERENCES "builder_artifacts"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "artifact_revisions" ADD CONSTRAINT "artifact_revisions_parent_revision_id_fkey" FOREIGN KEY ("parent_revision_id") REFERENCES "artifact_revisions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE "artifact_dependencies" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "source_revision_id" TEXT NOT NULL,
  "alias" TEXT NOT NULL,
  "target_kind" TEXT NOT NULL,
  "target_coordinate" TEXT NOT NULL,
  "version_range" TEXT NOT NULL,
  "target_artifact_id" TEXT,
  "optional" BOOLEAN NOT NULL DEFAULT false,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "artifact_dependencies_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "artifact_dependencies_source_revision_id_alias_key" ON "artifact_dependencies"("source_revision_id", "alias");
CREATE INDEX "artifact_dependencies_tenant_id_target_coordinate_idx" ON "artifact_dependencies"("tenant_id", "target_coordinate");
CREATE INDEX "artifact_dependencies_tenant_id_target_artifact_id_idx" ON "artifact_dependencies"("tenant_id", "target_artifact_id");
ALTER TABLE "artifact_dependencies" ADD CONSTRAINT "artifact_dependencies_source_revision_id_fkey" FOREIGN KEY ("source_revision_id") REFERENCES "artifact_revisions"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "artifact_dependencies" ADD CONSTRAINT "artifact_dependencies_target_artifact_id_fkey" FOREIGN KEY ("target_artifact_id") REFERENCES "builder_artifacts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE "artifact_builds" (
  "id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "revision_id" TEXT NOT NULL,
  "compiler_id" TEXT NOT NULL, "compiler_version" TEXT NOT NULL,
  "source_hash" TEXT NOT NULL, "output_hash" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'SUCCESS', "diagnostics" JSONB NOT NULL DEFAULT '[]',
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "artifact_builds_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "artifact_builds_revision_id_compiler_id_compiler_version_key" ON "artifact_builds"("revision_id", "compiler_id", "compiler_version");
CREATE INDEX "artifact_builds_tenant_id_output_hash_idx" ON "artifact_builds"("tenant_id", "output_hash");
ALTER TABLE "artifact_builds" ADD CONSTRAINT "artifact_builds_revision_id_fkey" FOREIGN KEY ("revision_id") REFERENCES "artifact_revisions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "dev_packages" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "namespace" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "description" TEXT,
  "visibility" TEXT NOT NULL DEFAULT 'PRIVATE',
  "editability" TEXT NOT NULL DEFAULT 'INTERNAL',
  "status" TEXT NOT NULL DEFAULT 'ACTIVE',
  "created_by" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "dev_packages_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "dev_packages_tenant_id_namespace_name_key" ON "dev_packages"("tenant_id", "namespace", "name");
CREATE INDEX "dev_packages_tenant_id_visibility_status_idx" ON "dev_packages"("tenant_id", "visibility", "status");

CREATE TABLE "dev_signing_keys" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "key_id" TEXT NOT NULL,
  "algorithm" TEXT NOT NULL DEFAULT 'Ed25519',
  "public_key" TEXT NOT NULL,
  "label" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'ACTIVE',
  "created_by" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "revoked_at" TIMESTAMP(3),
  CONSTRAINT "dev_signing_keys_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "dev_signing_keys_tenant_id_key_id_key" ON "dev_signing_keys"("tenant_id", "key_id");
CREATE INDEX "dev_signing_keys_tenant_id_status_idx" ON "dev_signing_keys"("tenant_id", "status");

CREATE TABLE "dev_package_versions" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "package_id" TEXT NOT NULL,
  "version" TEXT NOT NULL,
  "manifest" JSONB NOT NULL,
  "content_hash" TEXT NOT NULL,
  "signature" TEXT,
  "required_capabilities" JSONB NOT NULL DEFAULT '[]',
  "compatibility" JSONB NOT NULL DEFAULT '{}',
  "license_expression" TEXT,
  "sbom_digest" TEXT,
  "vulnerability_status" TEXT NOT NULL DEFAULT 'UNKNOWN',
  "vulnerability_report" JSONB NOT NULL DEFAULT '[]',
  "status" TEXT NOT NULL DEFAULT 'DRAFT',
  "published_by" TEXT,
  "published_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "dev_package_versions_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "dev_package_versions_package_id_version_key" ON "dev_package_versions"("package_id", "version");
CREATE UNIQUE INDEX "dev_package_versions_tenant_id_content_hash_key" ON "dev_package_versions"("tenant_id", "content_hash");
CREATE INDEX "dev_package_versions_tenant_id_status_published_at_idx" ON "dev_package_versions"("tenant_id", "status", "published_at" DESC);
ALTER TABLE "dev_package_versions" ADD CONSTRAINT "dev_package_versions_package_id_fkey" FOREIGN KEY ("package_id") REFERENCES "dev_packages"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "dev_package_items" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "package_version_id" TEXT NOT NULL,
  "artifact_id" TEXT NOT NULL,
  "revision_id" TEXT NOT NULL,
  "export_name" TEXT NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "dev_package_items_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "dev_package_items_package_version_id_export_name_key" ON "dev_package_items"("package_version_id", "export_name");
CREATE UNIQUE INDEX "dev_package_items_package_version_id_artifact_id_key" ON "dev_package_items"("package_version_id", "artifact_id");
CREATE INDEX "dev_package_items_tenant_id_artifact_id_idx" ON "dev_package_items"("tenant_id", "artifact_id");
ALTER TABLE "dev_package_items" ADD CONSTRAINT "dev_package_items_package_version_id_fkey" FOREIGN KEY ("package_version_id") REFERENCES "dev_package_versions"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "dev_package_items" ADD CONSTRAINT "dev_package_items_artifact_id_fkey" FOREIGN KEY ("artifact_id") REFERENCES "builder_artifacts"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "dev_package_items" ADD CONSTRAINT "dev_package_items_revision_id_fkey" FOREIGN KEY ("revision_id") REFERENCES "artifact_revisions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE "package_certifications" (
  "id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "package_version_id" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'RUNNING', "report" JSONB NOT NULL DEFAULT '[]',
  "certified_by" TEXT, "certified_at" TIMESTAMP(3), "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "package_certifications_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "package_certifications_tenant_id_package_version_id_status_idx" ON "package_certifications"("tenant_id", "package_version_id", "status");
ALTER TABLE "package_certifications" ADD CONSTRAINT "package_certifications_package_version_id_fkey" FOREIGN KEY ("package_version_id") REFERENCES "dev_package_versions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "project_installations" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "project_id" TEXT NOT NULL,
  "package_id" TEXT NOT NULL,
  "package_version_id" TEXT NOT NULL,
  "mode" TEXT NOT NULL DEFAULT 'PINNED',
  "requested_range" TEXT,
  "lock" JSONB NOT NULL,
  "resource_mappings" JSONB NOT NULL DEFAULT '{}',
  "capability_grants" JSONB NOT NULL DEFAULT '[]',
  "status" TEXT NOT NULL DEFAULT 'ACTIVE',
  "installed_by" TEXT,
  "installed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  "removed_at" TIMESTAMP(3),
  CONSTRAINT "project_installations_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "project_installations_project_id_package_id_key" ON "project_installations"("project_id", "package_id");
CREATE INDEX "project_installations_tenant_id_project_id_status_idx" ON "project_installations"("tenant_id", "project_id", "status");
ALTER TABLE "project_installations" ADD CONSTRAINT "project_installations_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "dev_projects"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "project_installations" ADD CONSTRAINT "project_installations_package_id_fkey" FOREIGN KEY ("package_id") REFERENCES "dev_packages"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "project_installations" ADD CONSTRAINT "project_installations_package_version_id_fkey" FOREIGN KEY ("package_version_id") REFERENCES "dev_package_versions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE "project_validation_runs" (
  "id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "project_id" TEXT NOT NULL,
  "source_fingerprint" TEXT NOT NULL, "status" TEXT NOT NULL DEFAULT 'RUNNING',
  "score" INTEGER, "checks" JSONB NOT NULL DEFAULT '[]', "evidence" JSONB NOT NULL DEFAULT '[]',
  "started_by" TEXT, "started_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "completed_at" TIMESTAMP(3), CONSTRAINT "project_validation_runs_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "project_validation_runs_tenant_id_project_id_source_fingerprint_status_idx" ON "project_validation_runs"("tenant_id", "project_id", "source_fingerprint", "status");
ALTER TABLE "project_validation_runs" ADD CONSTRAINT "project_validation_runs_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "dev_projects"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "project_test_runs" (
  "id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "project_id" TEXT NOT NULL,
  "source_fingerprint" TEXT NOT NULL, "status" TEXT NOT NULL DEFAULT 'RUNNING',
  "summary" JSONB NOT NULL DEFAULT '{}', "evidence" JSONB NOT NULL DEFAULT '[]',
  "started_by" TEXT, "started_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "completed_at" TIMESTAMP(3), CONSTRAINT "project_test_runs_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "project_test_runs_tenant_id_project_id_source_fingerprint_status_idx" ON "project_test_runs"("tenant_id", "project_id", "source_fingerprint", "status");
ALTER TABLE "project_test_runs" ADD CONSTRAINT "project_test_runs_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "dev_projects"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "project_release_approvals" (
  "id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "project_id" TEXT NOT NULL,
  "release_id" TEXT NOT NULL, "user_id" TEXT NOT NULL, "status" TEXT NOT NULL DEFAULT 'APPROVED',
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "project_release_approvals_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "project_release_approvals_release_id_user_id_key" ON "project_release_approvals"("release_id", "user_id");
CREATE INDEX "project_release_approvals_tenant_id_project_id_release_id_status_idx" ON "project_release_approvals"("tenant_id", "project_id", "release_id", "status");
ALTER TABLE "project_release_approvals" ADD CONSTRAINT "project_release_approvals_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "dev_projects"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "project_release_approvals" ADD CONSTRAINT "project_release_approvals_release_id_fkey" FOREIGN KEY ("release_id") REFERENCES "project_releases"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "project_preview_sessions" (
  "id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "project_id" TEXT NOT NULL,
  "source_fingerprint" TEXT NOT NULL, "token_hash" TEXT NOT NULL, "context" JSONB NOT NULL DEFAULT '{}',
  "status" TEXT NOT NULL DEFAULT 'ACTIVE', "expires_at" TIMESTAMP(3) NOT NULL,
  "created_by" TEXT, "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "revoked_at" TIMESTAMP(3),
  CONSTRAINT "project_preview_sessions_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "project_preview_sessions_token_hash_key" ON "project_preview_sessions"("token_hash");
CREATE INDEX "project_preview_sessions_tenant_id_project_id_status_expires_at_idx" ON "project_preview_sessions"("tenant_id", "project_id", "status", "expires_at");
ALTER TABLE "project_preview_sessions" ADD CONSTRAINT "project_preview_sessions_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "dev_projects"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "developer_audit_events" (
  "id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "project_id" TEXT NOT NULL,
  "action" TEXT NOT NULL, "actor_id" TEXT, "correlation_id" TEXT,
  "metadata" JSONB NOT NULL DEFAULT '{}', "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "developer_audit_events_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "developer_audit_events_tenant_id_project_id_created_at_idx" ON "developer_audit_events"("tenant_id", "project_id", "created_at" DESC);
CREATE INDEX "developer_audit_events_tenant_id_action_created_at_idx" ON "developer_audit_events"("tenant_id", "action", "created_at" DESC);
ALTER TABLE "developer_audit_events" ADD CONSTRAINT "developer_audit_events_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "dev_projects"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "environment_bindings" (
  "id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "project_id" TEXT NOT NULL,
  "environment_id" TEXT NOT NULL, "key" TEXT NOT NULL, "kind" TEXT NOT NULL,
  "reference" TEXT NOT NULL, "required_capabilities" JSONB NOT NULL DEFAULT '[]',
  "status" TEXT NOT NULL DEFAULT 'UNVERIFIED', "verified_at" TIMESTAMP(3),
  "created_by" TEXT, "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL, CONSTRAINT "environment_bindings_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "environment_bindings_project_id_environment_id_key_key" ON "environment_bindings"("project_id", "environment_id", "key");
CREATE INDEX "environment_bindings_tenant_id_environment_id_status_idx" ON "environment_bindings"("tenant_id", "environment_id", "status");
ALTER TABLE "environment_bindings" ADD CONSTRAINT "environment_bindings_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "dev_projects"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "environment_bindings" ADD CONSTRAINT "environment_bindings_environment_id_fkey" FOREIGN KEY ("environment_id") REFERENCES "environments"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "runtime_cell_assignments" (
  "id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "cell_id" TEXT NOT NULL,
  "shard" INTEGER NOT NULL, "region" TEXT NOT NULL, "topology_version" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'ACTIVE', "relocation_count" INTEGER NOT NULL DEFAULT 0,
  "assigned_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "runtime_cell_assignments_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "runtime_cell_assignments_tenant_id_key" ON "runtime_cell_assignments"("tenant_id");
CREATE INDEX "runtime_cell_assignments_region_cell_id_status_idx" ON "runtime_cell_assignments"("region", "cell_id", "status");

CREATE TABLE "tenant_developer_entitlements" (
  "id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "limits" JSONB NOT NULL DEFAULT '{}',
  "status" TEXT NOT NULL DEFAULT 'ACTIVE', "updated_by" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "tenant_developer_entitlements_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "tenant_developer_entitlements_tenant_id_key" ON "tenant_developer_entitlements"("tenant_id");

CREATE TABLE "runtime_cell_assignment_events" (
  "id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "assignment_id" TEXT NOT NULL,
  "action" TEXT NOT NULL, "actor_id" TEXT, "previous" JSONB NOT NULL DEFAULT '{}',
  "target" JSONB NOT NULL DEFAULT '{}', "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "runtime_cell_assignment_events_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "runtime_cell_assignment_events_tenant_id_created_at_idx" ON "runtime_cell_assignment_events"("tenant_id", "created_at" DESC);
CREATE INDEX "runtime_cell_assignment_events_assignment_id_created_at_idx" ON "runtime_cell_assignment_events"("assignment_id", "created_at" DESC);
ALTER TABLE "runtime_cell_assignment_events" ADD CONSTRAINT "runtime_cell_assignment_events_assignment_id_fkey" FOREIGN KEY ("assignment_id") REFERENCES "runtime_cell_assignments"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "project_change_sets" (
  "id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "project_id" TEXT NOT NULL,
  "branch" TEXT NOT NULL, "title" TEXT NOT NULL, "description" TEXT,
  "bundle" JSONB NOT NULL, "bundle_hash" TEXT NOT NULL, "base_fingerprint" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'DRAFT', "created_by" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "submitted_at" TIMESTAMP(3),
  "merged_at" TIMESTAMP(3), "merged_by" TEXT,
  CONSTRAINT "project_change_sets_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "project_change_sets_tenant_id_project_id_status_created_at_idx" ON "project_change_sets"("tenant_id", "project_id", "status", "created_at" DESC);
ALTER TABLE "project_change_sets" ADD CONSTRAINT "project_change_sets_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "dev_projects"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "project_change_set_reviews" (
  "id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "change_set_id" TEXT NOT NULL,
  "reviewer_id" TEXT NOT NULL, "decision" TEXT NOT NULL, "comment" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "project_change_set_reviews_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "project_change_set_reviews_change_set_id_reviewer_id_key" ON "project_change_set_reviews"("change_set_id", "reviewer_id");
CREATE INDEX "project_change_set_reviews_tenant_id_change_set_id_decision_idx" ON "project_change_set_reviews"("tenant_id", "change_set_id", "decision");
ALTER TABLE "project_change_set_reviews" ADD CONSTRAINT "project_change_set_reviews_change_set_id_fkey" FOREIGN KEY ("change_set_id") REFERENCES "project_change_sets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "artifact_overlays" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "artifact_id" TEXT NOT NULL,
  "source_revision_id" TEXT NOT NULL,
  "target_package_version_id" TEXT NOT NULL,
  "patch" JSONB NOT NULL,
  "content_hash" TEXT NOT NULL,
  "conflict_status" TEXT NOT NULL DEFAULT 'CLEAN',
  "created_by" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "artifact_overlays_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "artifact_overlays_artifact_id_target_package_version_id_content_hash_key" ON "artifact_overlays"("artifact_id", "target_package_version_id", "content_hash");
CREATE INDEX "artifact_overlays_tenant_id_target_package_version_id_idx" ON "artifact_overlays"("tenant_id", "target_package_version_id");
ALTER TABLE "artifact_overlays" ADD CONSTRAINT "artifact_overlays_artifact_id_fkey" FOREIGN KEY ("artifact_id") REFERENCES "builder_artifacts"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "artifact_overlays" ADD CONSTRAINT "artifact_overlays_source_revision_id_fkey" FOREIGN KEY ("source_revision_id") REFERENCES "artifact_revisions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "artifact_overlays" ADD CONSTRAINT "artifact_overlays_target_package_version_id_fkey" FOREIGN KEY ("target_package_version_id") REFERENCES "dev_package_versions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "project_releases" ADD COLUMN "manifest_hash" TEXT;
ALTER TABLE "project_releases" ADD COLUMN "signature" TEXT;
ALTER TABLE "project_releases" ADD COLUMN "signing_key_id" TEXT;
ALTER TABLE "project_releases" ADD COLUMN "source_fingerprint" TEXT;
ALTER TABLE "project_releases" ADD COLUMN "policy_bundle_version" TEXT;
CREATE INDEX "project_releases_tenant_id_manifest_hash_idx" ON "project_releases"("tenant_id", "manifest_hash");

-- All new rows are tenant-owned. No service or pre-authentication exception.
DO $$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'artifact_revisions', 'artifact_dependencies', 'artifact_builds', 'dev_packages', 'dev_signing_keys', 'package_certifications',
    'dev_package_versions', 'dev_package_items', 'project_installations',
    'artifact_overlays', 'project_validation_runs', 'project_test_runs', 'project_release_approvals', 'project_preview_sessions', 'developer_audit_events', 'environment_bindings', 'runtime_cell_assignments', 'runtime_cell_assignment_events', 'tenant_developer_entitlements', 'project_change_sets', 'project_change_set_reviews'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', table_name);
    EXECUTE format(
      'CREATE POLICY %I ON %I USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id())',
      'tenant_isolation_' || table_name, table_name
    );
  END LOOP;
END $$;
