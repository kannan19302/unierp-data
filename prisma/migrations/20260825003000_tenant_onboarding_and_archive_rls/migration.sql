-- CreateTable: tenant_onboarding_progress
CREATE TABLE IF NOT EXISTS "tenant_onboarding_progress" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "current_step" TEXT NOT NULL DEFAULT 'ORGANIZATION_PROFILE',
  "completed_steps" TEXT[] DEFAULT ARRAY[]::TEXT[],
  "percent_complete" INTEGER NOT NULL DEFAULT 0,
  "industry_template" TEXT,
  "currency_set" BOOLEAN NOT NULL DEFAULT false,
  "chart_of_accounts_set" BOOLEAN NOT NULL DEFAULT false,
  "team_invited" BOOLEAN NOT NULL DEFAULT false,
  "data_imported" BOOLEAN NOT NULL DEFAULT false,
  "first_transaction_at" TIMESTAMP(3),
  "is_completed" BOOLEAN NOT NULL DEFAULT false,
  "completed_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "tenant_onboarding_progress_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "tenant_onboarding_progress_tenant_id_key" ON "tenant_onboarding_progress"("tenant_id");
CREATE INDEX IF NOT EXISTS "tenant_onboarding_progress_tenant_id_idx" ON "tenant_onboarding_progress"("tenant_id");

-- CreateTable: master_data_import_jobs
CREATE TABLE IF NOT EXISTS "master_data_import_jobs" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "entity_type" TEXT NOT NULL,
  "file_name" TEXT NOT NULL,
  "file_size" INTEGER NOT NULL,
  "total_rows" INTEGER NOT NULL DEFAULT 0,
  "processed_rows" INTEGER NOT NULL DEFAULT 0,
  "success_rows" INTEGER NOT NULL DEFAULT 0,
  "error_rows" INTEGER NOT NULL DEFAULT 0,
  "error_details" JSONB,
  "field_mappings" JSONB NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'PENDING',
  "started_at" TIMESTAMP(3),
  "completed_at" TIMESTAMP(3),
  "created_by" TEXT NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "master_data_import_jobs_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "master_data_import_jobs_tenant_id_entity_type_idx" ON "master_data_import_jobs"("tenant_id", "entity_type");

-- RLS & Policies: tenant_onboarding_progress
ALTER TABLE "tenant_onboarding_progress" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tenant_onboarding_progress" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_tenant_onboarding_progress" ON "tenant_onboarding_progress";
CREATE POLICY "tenant_isolation_tenant_onboarding_progress" ON "tenant_onboarding_progress"
  FOR ALL
  USING ("tenant_id" = current_tenant_id())
  WITH CHECK ("tenant_id" = current_tenant_id());

-- RLS & Policies: master_data_import_jobs
ALTER TABLE "master_data_import_jobs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "master_data_import_jobs" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_master_data_import_jobs" ON "master_data_import_jobs";
CREATE POLICY "tenant_isolation_master_data_import_jobs" ON "master_data_import_jobs"
  FOR ALL
  USING ("tenant_id" = current_tenant_id())
  WITH CHECK ("tenant_id" = current_tenant_id());

-- RLS & Policies: builder_modules_json_archive_p8_v2
ALTER TABLE "builder_modules_json_archive_p8_v2" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "builder_modules_json_archive_p8_v2" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_builder_modules_json_archive_p8_v2" ON "builder_modules_json_archive_p8_v2";
CREATE POLICY "tenant_isolation_builder_modules_json_archive_p8_v2" ON "builder_modules_json_archive_p8_v2"
  FOR ALL
  USING ("tenant_id" = current_tenant_id())
  WITH CHECK ("tenant_id" = current_tenant_id());

-- Grants to unerp_api
GRANT SELECT, INSERT, UPDATE, DELETE ON "tenant_onboarding_progress" TO unerp_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON "master_data_import_jobs" TO unerp_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON "builder_modules_json_archive_p8_v2" TO unerp_api;
