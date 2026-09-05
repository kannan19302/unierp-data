-- ============================================================
-- UniERP Migration: 20260904000000_analytics_persistence_repair
-- Comprehensive Analytics Persistence Repair & RLS Hardening
-- ============================================================

-- 1. ADD ORG_ID AND AUDIT COLUMNS TO PARENT TABLES FIRST
-- ------------------------------------------------------------
ALTER TABLE "analytics_custom_dashboards" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "reporting_templates_deep" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "reporting_export_jobs" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "reporting_compliance_audits" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "reporting_distribution_lists" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "analytics_cohort_analyses" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "analytics_predictive_models" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "reporting_scheduled_jobs_deep" ADD COLUMN IF NOT EXISTS "org_id" TEXT;

-- 2. EXPAND & BACKFILL CHILD TENANT COLUMNS
-- ------------------------------------------------------------

-- analytics_dashboard_widgets_deep
ALTER TABLE "analytics_dashboard_widgets_deep" ADD COLUMN IF NOT EXISTS "tenant_id" TEXT;
ALTER TABLE "analytics_dashboard_widgets_deep" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "analytics_dashboard_widgets_deep" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_dashboard_widgets_deep" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "analytics_dashboard_widgets_deep" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);
ALTER TABLE "analytics_dashboard_widgets_deep" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

UPDATE "analytics_dashboard_widgets_deep" w
SET "tenant_id" = d."tenant_id", "org_id" = d."org_id"
FROM "analytics_custom_dashboards" d
WHERE w."dashboard_id" = d."id" AND w."tenant_id" IS NULL;

UPDATE "analytics_dashboard_widgets_deep"
SET "tenant_id" = 'system-orphan-tenant'
WHERE "tenant_id" IS NULL;

-- reporting_template_sections
ALTER TABLE "reporting_template_sections" ADD COLUMN IF NOT EXISTS "tenant_id" TEXT;
ALTER TABLE "reporting_template_sections" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "reporting_template_sections" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "reporting_template_sections" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "reporting_template_sections" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);
ALTER TABLE "reporting_template_sections" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

UPDATE "reporting_template_sections" s
SET "tenant_id" = t."tenant_id", "org_id" = t."org_id"
FROM "reporting_templates_deep" t
WHERE s."template_id" = t."id" AND s."tenant_id" IS NULL;

UPDATE "reporting_template_sections"
SET "tenant_id" = 'system-orphan-tenant'
WHERE "tenant_id" IS NULL;

-- reporting_export_files
ALTER TABLE "reporting_export_files" ADD COLUMN IF NOT EXISTS "tenant_id" TEXT;
ALTER TABLE "reporting_export_files" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "reporting_export_files" ADD COLUMN IF NOT EXISTS "sha256_checksum" TEXT;
ALTER TABLE "reporting_export_files" ADD COLUMN IF NOT EXISTS "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE "reporting_export_files" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

UPDATE "reporting_export_files" f
SET "tenant_id" = j."tenant_id", "org_id" = j."org_id"
FROM "reporting_export_jobs" j
WHERE f."export_job_id" = j."id" AND f."tenant_id" IS NULL;

UPDATE "reporting_export_files"
SET "tenant_id" = 'system-orphan-tenant'
WHERE "tenant_id" IS NULL;

-- reporting_signoff_history
ALTER TABLE "reporting_signoff_history" ADD COLUMN IF NOT EXISTS "tenant_id" TEXT;
ALTER TABLE "reporting_signoff_history" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "reporting_signoff_history" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;

UPDATE "reporting_signoff_history" h
SET "tenant_id" = a."tenant_id", "org_id" = a."org_id"
FROM "reporting_compliance_audits" a
WHERE h."audit_id" = a."id" AND h."tenant_id" IS NULL;

UPDATE "reporting_signoff_history"
SET "tenant_id" = 'system-orphan-tenant'
WHERE "tenant_id" IS NULL;

-- reporting_distribution_recipients
ALTER TABLE "reporting_distribution_recipients" ADD COLUMN IF NOT EXISTS "tenant_id" TEXT;
ALTER TABLE "reporting_distribution_recipients" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "reporting_distribution_recipients" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "reporting_distribution_recipients" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

UPDATE "reporting_distribution_recipients" r
SET "tenant_id" = l."tenant_id", "org_id" = l."org_id"
FROM "reporting_distribution_lists" l
WHERE r."list_id" = l."id" AND r."tenant_id" IS NULL;

UPDATE "reporting_distribution_recipients"
SET "tenant_id" = 'system-orphan-tenant'
WHERE "tenant_id" IS NULL;

-- 3. ENFORCE NOT NULL ON TENANT_ID
-- ------------------------------------------------------------
ALTER TABLE "analytics_dashboard_widgets_deep" ALTER COLUMN "tenant_id" SET NOT NULL;
ALTER TABLE "reporting_template_sections" ALTER COLUMN "tenant_id" SET NOT NULL;
ALTER TABLE "reporting_export_files" ALTER COLUMN "tenant_id" SET NOT NULL;
ALTER TABLE "reporting_signoff_history" ALTER COLUMN "tenant_id" SET NOT NULL;
ALTER TABLE "reporting_distribution_recipients" ALTER COLUMN "tenant_id" SET NOT NULL;

-- 4. EXPAND ADDITIVE GOVERNANCE, AUDIT, METRIC, DECIMAL & LIFECYCLE FIELDS
-- ------------------------------------------------------------

-- dashboards
ALTER TABLE "dashboards" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "dashboards" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "dashboards" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);

-- reports
ALTER TABLE "reports" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "reports" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "reports" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);

-- kpis
ALTER TABLE "kpis" ADD COLUMN IF NOT EXISTS "numeric_value" DECIMAL(19,4);
ALTER TABLE "kpis" ADD COLUMN IF NOT EXISTS "target_value" DECIMAL(19,4);
ALTER TABLE "kpis" ADD COLUMN IF NOT EXISTS "currency" TEXT;
ALTER TABLE "kpis" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "kpis" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "kpis" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);

UPDATE "kpis"
SET "numeric_value" = CASE
  WHEN "value" ~ '^\$?[0-9]+(\.[0-9]+)?$' THEN regexp_replace("value", '^\$', '')::decimal(19,4)
  ELSE NULL
END
WHERE "numeric_value" IS NULL;

-- analytics_report_filters
ALTER TABLE "analytics_report_filters" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "analytics_report_filters" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_report_filters" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "analytics_report_filters" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);
ALTER TABLE "analytics_report_filters" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- analytics_dashboard_widgets
ALTER TABLE "analytics_dashboard_widgets" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "analytics_dashboard_widgets" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_dashboard_widgets" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "analytics_dashboard_widgets" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);

-- analytics_kpi_values
ALTER TABLE "analytics_kpi_values" ALTER COLUMN "value" TYPE DECIMAL(19,4);
ALTER TABLE "analytics_kpi_values" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "analytics_kpi_values" ADD COLUMN IF NOT EXISTS "currency" TEXT;
ALTER TABLE "analytics_kpi_values" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_kpi_values" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- analytics_scheduled_exports
ALTER TABLE "analytics_scheduled_exports" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "analytics_scheduled_exports" ADD COLUMN IF NOT EXISTS "expires_at" TIMESTAMP(3);
ALTER TABLE "analytics_scheduled_exports" ADD COLUMN IF NOT EXISTS "sha256_checksum" TEXT;
ALTER TABLE "analytics_scheduled_exports" ADD COLUMN IF NOT EXISTS "artifact_uri" TEXT;
ALTER TABLE "analytics_scheduled_exports" ADD COLUMN IF NOT EXISTS "file_size_bytes" INTEGER;
ALTER TABLE "analytics_scheduled_exports" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_scheduled_exports" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "analytics_scheduled_exports" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);

-- analytics_kpi_definitions
ALTER TABLE "analytics_kpi_definitions" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "analytics_kpi_definitions" ADD COLUMN IF NOT EXISTS "target_value" DECIMAL(19,4);
ALTER TABLE "analytics_kpi_definitions" ADD COLUMN IF NOT EXISTS "currency" TEXT;
ALTER TABLE "analytics_kpi_definitions" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_kpi_definitions" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "analytics_kpi_definitions" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);

-- analytics_trend_results
ALTER TABLE "analytics_trend_results" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "analytics_trend_results" ADD COLUMN IF NOT EXISTS "exact_value" DECIMAL(19,4);
ALTER TABLE "analytics_trend_results" ADD COLUMN IF NOT EXISTS "exact_previous_value" DECIMAL(19,4);
ALTER TABLE "analytics_trend_results" ADD COLUMN IF NOT EXISTS "currency" TEXT;
ALTER TABLE "analytics_trend_results" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_trend_results" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

UPDATE "analytics_trend_results"
SET "exact_value" = "value"::decimal(19,4)
WHERE "exact_value" IS NULL AND "value" IS NOT NULL;

-- analytics_cross_filter_dashboards
ALTER TABLE "analytics_cross_filter_dashboards" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "analytics_cross_filter_dashboards" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_cross_filter_dashboards" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "analytics_cross_filter_dashboards" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);

-- analytics_bi_metric_definitions
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "version" TEXT NOT NULL DEFAULT '1.0.0';
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "version_number" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "owner_id" TEXT;
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "owner_email" TEXT;
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "certification_level" TEXT NOT NULL DEFAULT 'UNCERTIFIED';
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "certified_by" TEXT;
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "certified_at" TIMESTAMP(3);
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "lineage_sources" JSONB;
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "freshness_schedule" TEXT;
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "freshness_sla_minutes" INTEGER;
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "last_refreshed_at" TIMESTAMP(3);
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "privacy_classification" TEXT NOT NULL DEFAULT 'INTERNAL';
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "quality_score" DECIMAL(5,2);
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "effective_from" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "effective_to" TIMESTAMP(3);
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "currency" TEXT;
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "analytics_bi_metric_definitions" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);

-- core-part-13 remaining models
ALTER TABLE "analytics_custom_dashboards" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_custom_dashboards" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "analytics_custom_dashboards" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);

ALTER TABLE "analytics_data_datasets" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "analytics_data_datasets" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_data_datasets" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "analytics_data_datasets" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);
ALTER TABLE "analytics_data_datasets" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE "analytics_data_pipelines" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "analytics_data_pipelines" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_data_pipelines" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "analytics_data_pipelines" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);
ALTER TABLE "analytics_data_pipelines" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE "analytics_predictive_models" ALTER COLUMN "accuracy_score" TYPE DECIMAL(19,4);
ALTER TABLE "analytics_predictive_models" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_predictive_models" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "analytics_predictive_models" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);
ALTER TABLE "analytics_predictive_models" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE "analytics_forecast_runs" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "analytics_forecast_runs" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_forecast_runs" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "analytics_forecast_runs" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);
ALTER TABLE "analytics_forecast_runs" ADD COLUMN IF NOT EXISTS "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE "analytics_forecast_runs" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE "analytics_cohort_analyses" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_cohort_analyses" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "analytics_cohort_analyses" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);
ALTER TABLE "analytics_cohort_analyses" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE "analytics_cohort_groups" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "analytics_cohort_groups" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_cohort_groups" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "analytics_cohort_groups" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);
ALTER TABLE "analytics_cohort_groups" ADD COLUMN IF NOT EXISTS "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE "analytics_cohort_groups" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE "analytics_funnel_steps" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "analytics_funnel_steps" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_funnel_steps" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "analytics_funnel_steps" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);
ALTER TABLE "analytics_funnel_steps" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE "analytics_funnel_conversions" ALTER COLUMN "overall_dropoff" TYPE DECIMAL(19,4);
ALTER TABLE "analytics_funnel_conversions" ADD COLUMN IF NOT EXISTS "conversion_rate" DECIMAL(19,4);
ALTER TABLE "analytics_funnel_conversions" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "analytics_funnel_conversions" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "analytics_funnel_conversions" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "analytics_funnel_conversions" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);
ALTER TABLE "analytics_funnel_conversions" ADD COLUMN IF NOT EXISTS "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE "analytics_funnel_conversions" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE "reporting_templates_deep" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "reporting_templates_deep" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "reporting_templates_deep" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);

ALTER TABLE "reporting_scheduled_jobs_deep" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "reporting_scheduled_jobs_deep" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "reporting_scheduled_jobs_deep" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);
ALTER TABLE "reporting_scheduled_jobs_deep" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE "reporting_execution_logs" ADD COLUMN IF NOT EXISTS "org_id" TEXT;
ALTER TABLE "reporting_execution_logs" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;

ALTER TABLE "reporting_export_jobs" ADD COLUMN IF NOT EXISTS "expires_at" TIMESTAMP(3);
ALTER TABLE "reporting_export_jobs" ADD COLUMN IF NOT EXISTS "sha256_checksum" TEXT;
ALTER TABLE "reporting_export_jobs" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "reporting_export_jobs" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "reporting_export_jobs" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);
ALTER TABLE "reporting_export_jobs" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE "reporting_compliance_audits" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "reporting_compliance_audits" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "reporting_compliance_audits" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);
ALTER TABLE "reporting_compliance_audits" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE "reporting_distribution_lists" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "reporting_distribution_lists" ADD COLUMN IF NOT EXISTS "is_deleted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "reporting_distribution_lists" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);
ALTER TABLE "reporting_distribution_lists" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- 5. FOREIGN KEYS & CONSTRAINTS
-- ------------------------------------------------------------
ALTER TABLE "analytics_dashboard_widgets_deep" DROP CONSTRAINT IF EXISTS "analytics_dashboard_widgets_deep_dashboard_id_fkey";
ALTER TABLE "analytics_dashboard_widgets_deep" ADD CONSTRAINT "analytics_dashboard_widgets_deep_dashboard_id_fkey" FOREIGN KEY ("dashboard_id") REFERENCES "analytics_custom_dashboards"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "reporting_template_sections" DROP CONSTRAINT IF EXISTS "reporting_template_sections_template_id_fkey";
ALTER TABLE "reporting_template_sections" ADD CONSTRAINT "reporting_template_sections_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "reporting_templates_deep"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "reporting_scheduled_jobs_deep" DROP CONSTRAINT IF EXISTS "reporting_scheduled_jobs_deep_template_id_fkey";
ALTER TABLE "reporting_scheduled_jobs_deep" ADD CONSTRAINT "reporting_scheduled_jobs_deep_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "reporting_templates_deep"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "reporting_execution_logs" DROP CONSTRAINT IF EXISTS "reporting_execution_logs_job_id_fkey";
ALTER TABLE "reporting_execution_logs" ADD CONSTRAINT "reporting_execution_logs_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "reporting_scheduled_jobs_deep"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "reporting_export_files" DROP CONSTRAINT IF EXISTS "reporting_export_files_export_job_id_fkey";
ALTER TABLE "reporting_export_files" ADD CONSTRAINT "reporting_export_files_export_job_id_fkey" FOREIGN KEY ("export_job_id") REFERENCES "reporting_export_jobs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "reporting_signoff_history" DROP CONSTRAINT IF EXISTS "reporting_signoff_history_audit_id_fkey";
ALTER TABLE "reporting_signoff_history" ADD CONSTRAINT "reporting_signoff_history_audit_id_fkey" FOREIGN KEY ("audit_id") REFERENCES "reporting_compliance_audits"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "reporting_distribution_recipients" DROP CONSTRAINT IF EXISTS "reporting_distribution_recipients_list_id_fkey";
ALTER TABLE "reporting_distribution_recipients" ADD CONSTRAINT "reporting_distribution_recipients_list_id_fkey" FOREIGN KEY ("list_id") REFERENCES "reporting_distribution_lists"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "analytics_cohort_groups" DROP CONSTRAINT IF EXISTS "analytics_cohort_groups_analysis_id_fkey";
ALTER TABLE "analytics_cohort_groups" ADD CONSTRAINT "analytics_cohort_groups_analysis_id_fkey" FOREIGN KEY ("analysis_id") REFERENCES "analytics_cohort_analyses"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "analytics_forecast_runs" DROP CONSTRAINT IF EXISTS "analytics_forecast_runs_model_id_fkey";
ALTER TABLE "analytics_forecast_runs" ADD CONSTRAINT "analytics_forecast_runs_model_id_fkey" FOREIGN KEY ("model_id") REFERENCES "analytics_predictive_models"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "analytics_data_pipelines" DROP CONSTRAINT IF EXISTS "analytics_data_pipelines_source_dataset_id_fkey";
ALTER TABLE "analytics_data_pipelines" ADD CONSTRAINT "analytics_data_pipelines_source_dataset_id_fkey" FOREIGN KEY ("source_dataset_id") REFERENCES "analytics_data_datasets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "analytics_data_pipelines" DROP CONSTRAINT IF EXISTS "analytics_data_pipelines_target_dataset_id_fkey";
ALTER TABLE "analytics_data_pipelines" ADD CONSTRAINT "analytics_data_pipelines_target_dataset_id_fkey" FOREIGN KEY ("target_dataset_id") REFERENCES "analytics_data_datasets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Unique constraint on funnel steps:
ALTER TABLE "analytics_funnel_steps" DROP CONSTRAINT IF EXISTS "analytics_funnel_steps_tenant_funnel_order_key";
ALTER TABLE "analytics_funnel_steps" ADD CONSTRAINT "analytics_funnel_steps_tenant_funnel_order_key" UNIQUE ("tenant_id", "funnel_name", "step_order");

-- 6. INDEXES FOR PERFORMANCE & TENANCY
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS "dashboards_tenant_id_org_id_idx" ON "dashboards"("tenant_id", "org_id");
CREATE INDEX IF NOT EXISTS "dashboards_tenant_id_created_at_idx" ON "dashboards"("tenant_id", "created_at");
CREATE INDEX IF NOT EXISTS "reports_tenant_id_org_id_idx" ON "reports"("tenant_id", "org_id");
CREATE INDEX IF NOT EXISTS "reports_tenant_id_created_at_idx" ON "reports"("tenant_id", "created_at");
CREATE INDEX IF NOT EXISTS "kpis_tenant_id_org_id_is_deleted_idx" ON "kpis"("tenant_id", "org_id", "is_deleted");
CREATE INDEX IF NOT EXISTS "analytics_custom_dashboards_tenant_id_idx" ON "analytics_custom_dashboards"("tenant_id");
CREATE INDEX IF NOT EXISTS "analytics_dashboard_widgets_deep_tenant_id_idx" ON "analytics_dashboard_widgets_deep"("tenant_id");
CREATE INDEX IF NOT EXISTS "analytics_dashboard_widgets_deep_dashboard_id_idx" ON "analytics_dashboard_widgets_deep"("dashboard_id");
CREATE INDEX IF NOT EXISTS "analytics_data_datasets_tenant_id_idx" ON "analytics_data_datasets"("tenant_id");
CREATE INDEX IF NOT EXISTS "analytics_data_pipelines_tenant_id_idx" ON "analytics_data_pipelines"("tenant_id");
CREATE INDEX IF NOT EXISTS "analytics_predictive_models_tenant_id_idx" ON "analytics_predictive_models"("tenant_id");
CREATE INDEX IF NOT EXISTS "analytics_forecast_runs_tenant_id_idx" ON "analytics_forecast_runs"("tenant_id");
CREATE INDEX IF NOT EXISTS "analytics_forecast_runs_model_id_idx" ON "analytics_forecast_runs"("model_id");
CREATE INDEX IF NOT EXISTS "analytics_cohort_analyses_tenant_id_idx" ON "analytics_cohort_analyses"("tenant_id");
CREATE INDEX IF NOT EXISTS "analytics_cohort_groups_tenant_id_idx" ON "analytics_cohort_groups"("tenant_id");
CREATE INDEX IF NOT EXISTS "analytics_cohort_groups_analysis_id_idx" ON "analytics_cohort_groups"("analysis_id");
CREATE INDEX IF NOT EXISTS "analytics_funnel_steps_tenant_id_idx" ON "analytics_funnel_steps"("tenant_id");
CREATE INDEX IF NOT EXISTS "analytics_funnel_steps_tenant_id_funnel_name_idx" ON "analytics_funnel_steps"("tenant_id", "funnel_name");
CREATE INDEX IF NOT EXISTS "analytics_funnel_conversions_tenant_id_idx" ON "analytics_funnel_conversions"("tenant_id");
CREATE INDEX IF NOT EXISTS "analytics_funnel_conversions_tenant_funnel_period_idx" ON "analytics_funnel_conversions"("tenant_id", "funnel_name", "period");
CREATE INDEX IF NOT EXISTS "reporting_templates_deep_tenant_id_idx" ON "reporting_templates_deep"("tenant_id");
CREATE INDEX IF NOT EXISTS "reporting_template_sections_tenant_id_idx" ON "reporting_template_sections"("tenant_id");
CREATE INDEX IF NOT EXISTS "reporting_template_sections_template_id_idx" ON "reporting_template_sections"("template_id");
CREATE INDEX IF NOT EXISTS "reporting_scheduled_jobs_deep_tenant_id_idx" ON "reporting_scheduled_jobs_deep"("tenant_id");
CREATE INDEX IF NOT EXISTS "reporting_execution_logs_tenant_id_idx" ON "reporting_execution_logs"("tenant_id");
CREATE INDEX IF NOT EXISTS "reporting_export_jobs_tenant_id_idx" ON "reporting_export_jobs"("tenant_id");
CREATE INDEX IF NOT EXISTS "reporting_export_files_tenant_id_idx" ON "reporting_export_files"("tenant_id");
CREATE INDEX IF NOT EXISTS "reporting_export_files_export_job_id_idx" ON "reporting_export_files"("export_job_id");
CREATE INDEX IF NOT EXISTS "reporting_compliance_audits_tenant_id_idx" ON "reporting_compliance_audits"("tenant_id");
CREATE INDEX IF NOT EXISTS "reporting_signoff_history_tenant_id_idx" ON "reporting_signoff_history"("tenant_id");
CREATE INDEX IF NOT EXISTS "reporting_signoff_history_audit_id_idx" ON "reporting_signoff_history"("audit_id");
CREATE INDEX IF NOT EXISTS "reporting_distribution_lists_tenant_id_idx" ON "reporting_distribution_lists"("tenant_id");
CREATE INDEX IF NOT EXISTS "reporting_distribution_recipients_tenant_id_idx" ON "reporting_distribution_recipients"("tenant_id");
CREATE INDEX IF NOT EXISTS "reporting_distribution_recipients_list_id_idx" ON "reporting_distribution_recipients"("list_id");

-- 7. ROW LEVEL SECURITY ENFORCEMENT & POLICIES
-- ------------------------------------------------------------

-- analytics_dashboard_widgets_deep
ALTER TABLE "analytics_dashboard_widgets_deep" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "analytics_dashboard_widgets_deep" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_analytics_dashboard_widgets_deep" ON "analytics_dashboard_widgets_deep";
CREATE POLICY "tenant_isolation_analytics_dashboard_widgets_deep" ON "analytics_dashboard_widgets_deep"
  FOR ALL USING ("tenant_id" = current_tenant_id()) WITH CHECK ("tenant_id" = current_tenant_id());

-- reporting_template_sections
ALTER TABLE "reporting_template_sections" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "reporting_template_sections" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_reporting_template_sections" ON "reporting_template_sections";
CREATE POLICY "tenant_isolation_reporting_template_sections" ON "reporting_template_sections"
  FOR ALL USING ("tenant_id" = current_tenant_id()) WITH CHECK ("tenant_id" = current_tenant_id());

-- reporting_export_files
ALTER TABLE "reporting_export_files" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "reporting_export_files" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_reporting_export_files" ON "reporting_export_files";
CREATE POLICY "tenant_isolation_reporting_export_files" ON "reporting_export_files"
  FOR ALL USING ("tenant_id" = current_tenant_id()) WITH CHECK ("tenant_id" = current_tenant_id());

-- reporting_signoff_history
ALTER TABLE "reporting_signoff_history" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "reporting_signoff_history" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_reporting_signoff_history" ON "reporting_signoff_history";
CREATE POLICY "tenant_isolation_reporting_signoff_history" ON "reporting_signoff_history"
  FOR ALL USING ("tenant_id" = current_tenant_id()) WITH CHECK ("tenant_id" = current_tenant_id());

-- reporting_distribution_recipients
ALTER TABLE "reporting_distribution_recipients" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "reporting_distribution_recipients" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_reporting_distribution_recipients" ON "reporting_distribution_recipients";
CREATE POLICY "tenant_isolation_reporting_distribution_recipients" ON "reporting_distribution_recipients"
  FOR ALL USING ("tenant_id" = current_tenant_id()) WITH CHECK ("tenant_id" = current_tenant_id());

-- Grant privileges to unerp_api
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO unerp_api;
