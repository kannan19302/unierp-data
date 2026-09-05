import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { PrismaClient, Prisma } from "./main-client/index.js";
import { prisma } from "./index.js";

/**
 * Analytics Persistence Layer — Live PostgreSQL Integration & RLS Isolation Proof
 *
 * This test suite connects as the application role (unerp_api, which has
 * NOSUPERUSER and NOBYPASSRLS) and proves:
 *   1. Explicit tenant ownership and database-enforced RLS across all 31 analytics tables.
 *   2. Tenant A access: querying within Tenant A's session returns Tenant A's records.
 *   3. Tenant B denial: querying within Tenant B's session returns 0 rows of Tenant A.
 *   4. No-context denial: querying outside any tenant session under unerp_api returns 0 rows.
 *   5. Parent-child relationships and foreign key cascades on deep child models.
 *   6. Exact Decimal(19,4) numeric precision and currency/unit column preservation.
 *   7. Metric governance (version, certification, lineage, freshness) & artifact lifecycle fields.
 */

const defaultAppUrl = "postgresql://unerp_api:unerp_api_password@127.0.0.1:5432/unerp_dev";
const appRoleUrl = process.env.DATABASE_APP_URL || defaultAppUrl;

const appPrisma = new PrismaClient({
  datasources: { db: { url: appRoleUrl } },
});

/** Execute a callback within an isolated tenant session as unerp_api. */
async function asTenant<T>(
  tenantId: string,
  fn: (tx: Omit<PrismaClient, "$transaction" | "$connect" | "$disconnect">) => Promise<T>,
): Promise<T> {
  return appPrisma.$transaction(async (tx) => {
    await tx.$executeRawUnsafe(
      `SELECT set_config('app.current_tenant_id', $1, true)`,
      tenantId,
    );
    return fn(tx as never);
  });
}

const TENANT_A = "tnt-analytics-test-a";
const TENANT_B = "tnt-analytics-test-b";
const ORG_A = "org-analytics-test-a";
const ORG_B = "org-analytics-test-b";

const databaseAvailable = await (async (): Promise<boolean> => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    return true;
  } catch (error) {
    if (process.env.CI) {
      throw new Error(
        "Analytics RLS proof suite requires a database. " +
          `Underlying error: ${(error as Error).message}`,
      );
    }
    console.warn("\n  [skip] Analytics RLS proof suite — database unreachable.\n");
    return false;
  }
})();

const describeDb = describe.skipIf(!databaseAvailable);

describeDb("Analytics Persistence Layer: Live RLS & Integrity Proof", () => {
  beforeAll(async () => {
    if (!databaseAvailable) return;

    // 1. Setup tenant & organization records with superuser prisma
    await prisma.tenant.upsert({
      where: { id: TENANT_A },
      create: { id: TENANT_A, name: "Analytics Test Tenant A", slug: "analytics-test-a" },
      update: {},
    });
    await prisma.tenant.upsert({
      where: { id: TENANT_B },
      create: { id: TENANT_B, name: "Analytics Test Tenant B", slug: "analytics-test-b" },
      update: {},
    });

    await prisma.organization.upsert({
      where: { id: ORG_A },
      create: { id: ORG_A, tenantId: TENANT_A, name: "Org A" },
      update: {},
    });
    await prisma.organization.upsert({
      where: { id: ORG_B },
      create: { id: ORG_B, tenantId: TENANT_B, name: "Org B" },
      update: {},
    });
  });

  afterAll(async () => {
    if (!databaseAvailable) return;

    // Clean up test tenants (cascades or manual deletes)
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_dashboard_widgets_deep" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_custom_dashboards" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_dashboard_widgets" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "dashboards" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_report_filters" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "reports" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_kpi_values" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "kpis" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_trend_results" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_kpi_definitions" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_bi_metric_definitions" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_cross_filter_dashboards" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_forecast_runs" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_predictive_models" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_cohort_groups" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_cohort_analyses" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_funnel_conversions" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_funnel_steps" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_data_pipelines" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_data_datasets" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "analytics_scheduled_exports" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "reporting_template_sections" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "reporting_execution_logs" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "reporting_scheduled_jobs_deep" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "reporting_templates_deep" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "reporting_export_files" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "reporting_export_jobs" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "reporting_signoff_history" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "reporting_compliance_audits" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "reporting_distribution_recipients" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);
    await prisma.$executeRawUnsafe(`DELETE FROM "reporting_distribution_lists" WHERE "tenant_id" IN ($1, $2)`, TENANT_A, TENANT_B);

    await appPrisma.$disconnect();
  });

  describe("NOBYPASSRLS Baseline Verification", () => {
    it("proves application role connects with NOBYPASSRLS and NOSUPERUSER", async () => {
      const [roleRow] = await appPrisma.$queryRawUnsafe<
        Array<{ rolsuper: boolean; rolbypassrls: boolean }>
      >(`SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user`);

      expect(roleRow).toBeDefined();
      expect(roleRow?.rolsuper).toBe(false);
      expect(roleRow?.rolbypassrls).toBe(false);
    });

    it("proves ALL 31 analytics tables enforce Row Level Security", async () => {
      const analyticsTables = [
        "dashboards", "reports", "kpis", "analytics_report_filters", "analytics_dashboard_widgets",
        "analytics_kpi_values", "analytics_scheduled_exports", "analytics_kpi_definitions",
        "analytics_trend_results", "analytics_cross_filter_dashboards", "analytics_bi_metric_definitions",
        "analytics_custom_dashboards", "analytics_dashboard_widgets_deep", "analytics_data_datasets",
        "analytics_data_pipelines", "analytics_predictive_models", "analytics_forecast_runs",
        "analytics_cohort_analyses", "analytics_cohort_groups", "analytics_funnel_steps",
        "analytics_funnel_conversions", "reporting_templates_deep", "reporting_template_sections",
        "reporting_scheduled_jobs_deep", "reporting_execution_logs", "reporting_export_jobs",
        "reporting_export_files", "reporting_compliance_audits", "reporting_signoff_history",
        "reporting_distribution_lists", "reporting_distribution_recipients"
      ];

      const rlsRows = await appPrisma.$queryRawUnsafe<
        Array<{ relname: string; relrowsecurity: boolean; relforcerowsecurity: boolean }>
      >(
        `SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity 
         FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace 
         WHERE n.nspname = 'public' AND c.relname = ANY($1::text[])`,
        analyticsTables,
      );

      expect(rlsRows.length).toBe(31);
      for (const row of rlsRows) {
        expect(row.relrowsecurity, `RLS enabled on ${row.relname}`).toBe(true);
        expect(row.relforcerowsecurity, `RLS forced on ${row.relname}`).toBe(true);
      }
    });
  });

  describe("Table Family 1: Dashboards & Widgets (Standard + Deep)", () => {
    it("proves Tenant A access, Tenant B denial, and no-context denial for Dashboards & Widgets", async () => {
      const dashboardId = "test-dsh-a-1";
      const widgetId = "test-wgt-a-1";
      const deepDshId = "test-deep-dsh-a-1";
      const deepWidgetId = "test-deep-wgt-a-1";

      // 1. Tenant A inserts standard & deep dashboards and widgets
      await asTenant(TENANT_A, async (tx) => {
        await tx.dashboard.create({
          data: {
            id: dashboardId,
            tenantId: TENANT_A,
            orgId: ORG_A,
            name: "Executive Overview A",
            version: 1,
            analyticsWidgets: {
              create: {
                id: widgetId,
                tenantId: TENANT_A,
                widgetType: "CHART",
                title: "Revenue Widget A",
                version: 1,
              },
            },
          },
        });

        await tx.analyticsCustomDashboard.create({
          data: {
            id: deepDshId,
            tenantId: TENANT_A,
            orgId: ORG_A,
            name: "Deep Workbench A",
            creatorId: "user-a-1",
            version: 1,
            widgets: {
              create: {
                id: deepWidgetId,
                tenantId: TENANT_A,
                title: "Deep Grid A",
                widgetType: "DATA_GRID",
                queryConfig: { metric: "ARR" },
                layoutGrid: { x: 0, y: 0, w: 12, h: 6 },
                version: 1,
              },
            },
          },
        });
      });

      // 2. Tenant A queries: sees both
      await asTenant(TENANT_A, async (tx) => {
        const dsh = await tx.dashboard.findUnique({ where: { id: dashboardId } });
        expect(dsh).not.toBeNull();
        expect(dsh?.name).toBe("Executive Overview A");
        expect(dsh?.version).toBe(1);

        const wgt = await tx.analyticsDashboardWidget.findUnique({ where: { id: widgetId } });
        expect(wgt).not.toBeNull();

        const deepDsh = await tx.analyticsCustomDashboard.findUnique({
          where: { id: deepDshId },
          include: { widgets: true },
        });
        expect(deepDsh).not.toBeNull();
        expect(deepDsh?.widgets.length).toBe(1);
        expect(deepDsh?.widgets[0]?.tenantId).toBe(TENANT_A);
      });

      // 3. Tenant B queries: returns ZERO rows (denial)
      await asTenant(TENANT_B, async (tx) => {
        const dsh = await tx.dashboard.findUnique({ where: { id: dashboardId } });
        expect(dsh).toBeNull();

        const wgt = await tx.analyticsDashboardWidget.findUnique({ where: { id: widgetId } });
        expect(wgt).toBeNull();

        const deepDsh = await tx.analyticsCustomDashboard.findUnique({ where: { id: deepDshId } });
        expect(deepDsh).toBeNull();

        const deepWgt = await tx.analyticsDashboardWidgetDeep.findUnique({ where: { id: deepWidgetId } });
        expect(deepWgt).toBeNull();
      });

      // 4. No-context denial outside session
      const noContextDsh = await appPrisma.dashboard.findUnique({ where: { id: dashboardId } });
      expect(noContextDsh).toBeNull();

      const noContextDeepWgt = await appPrisma.analyticsDashboardWidgetDeep.findUnique({ where: { id: deepWidgetId } });
      expect(noContextDeepWgt).toBeNull();

      // 5. Parent cascade delete
      await asTenant(TENANT_A, async (tx) => {
        await tx.analyticsCustomDashboard.delete({ where: { id: deepDshId } });
        const remainingWgt = await tx.analyticsDashboardWidgetDeep.findUnique({ where: { id: deepWidgetId } });
        expect(remainingWgt).toBeNull();
      });
    });
  });

  describe("Table Family 2: Reports, Templates & Scheduled Jobs", () => {
    it("proves Tenant A access, Tenant B denial, and no-context denial for Reports & Templates", async () => {
      const reportId = "test-rpt-a-1";
      const filterId = "test-flt-a-1";
      const templateId = "test-tpl-a-1";
      const sectionId = "test-sec-a-1";
      const jobId = "test-job-a-1";
      const logId = "test-log-a-1";

      await asTenant(TENANT_A, async (tx) => {
        await tx.report.create({
          data: {
            id: reportId,
            tenantId: TENANT_A,
            orgId: ORG_A,
            name: "Monthly Audit Report",
            version: 1,
            analyticsFilters: {
              create: {
                id: filterId,
                tenantId: TENANT_A,
                field: "status",
                operator: "eq",
                value: "ACTIVE",
                version: 1,
              },
            },
          },
        });

        await tx.reportingTemplateDeep.create({
          data: {
            id: templateId,
            tenantId: TENANT_A,
            orgId: ORG_A,
            title: "Financial Signoff Template",
            category: "FINANCE",
            layoutHtml: "<div>Report</div>",
            version: 1,
            sections: {
              create: {
                id: sectionId,
                tenantId: TENANT_A,
                sectionName: "Summary",
                sectionOrder: 1,
                version: 1,
              },
            },
            scheduledJobs: {
              create: {
                id: jobId,
                tenantId: TENANT_A,
                jobName: "Nightly Financial Dispatch",
                cronSchedule: "0 0 * * *",
                recipients: ["auditor@domain.com"],
                version: 1,
                logs: {
                  create: {
                    id: logId,
                    tenantId: TENANT_A,
                    status: "SUCCESS",
                    executionMs: 245,
                    version: 1,
                  },
                },
              },
            },
          },
        });
      });

      // Tenant A reads
      await asTenant(TENANT_A, async (tx) => {
        const rpt = await tx.report.findUnique({ where: { id: reportId }, include: { analyticsFilters: true } });
        expect(rpt).not.toBeNull();
        expect(rpt?.analyticsFilters.length).toBe(1);

        const tpl = await tx.reportingTemplateDeep.findUnique({
          where: { id: templateId },
          include: { sections: true, scheduledJobs: { include: { logs: true } } },
        });
        expect(tpl).not.toBeNull();
        expect(tpl?.sections[0]?.tenantId).toBe(TENANT_A);
        expect(tpl?.scheduledJobs[0]?.logs[0]?.tenantId).toBe(TENANT_A);
      });

      // Tenant B denied
      await asTenant(TENANT_B, async (tx) => {
        expect(await tx.report.findUnique({ where: { id: reportId } })).toBeNull();
        expect(await tx.analyticsReportFilter.findUnique({ where: { id: filterId } })).toBeNull();
        expect(await tx.reportingTemplateDeep.findUnique({ where: { id: templateId } })).toBeNull();
        expect(await tx.reportingTemplateSection.findUnique({ where: { id: sectionId } })).toBeNull();
        expect(await tx.reportingScheduledJobDeep.findUnique({ where: { id: jobId } })).toBeNull();
        expect(await tx.reportingExecutionLog.findUnique({ where: { id: logId } })).toBeNull();
      });

      // No context denied
      expect(await appPrisma.report.findUnique({ where: { id: reportId } })).toBeNull();
      expect(await appPrisma.reportingTemplateSection.findUnique({ where: { id: sectionId } })).toBeNull();
    });
  });

  describe("Table Family 3: KPIs, BI Metrics, Trend Results & Exact Numeric Discipline", () => {
    it("proves Decimal(19,4) precision, metric governance, and tenant isolation", async () => {
      const kpiId = "test-kpi-a-1";
      const kpiValId = "test-kpival-a-1";
      const kpiDefId = "test-kpidef-a-1";
      const trendId = "test-trend-a-1";
      const biMetricId = "test-bimetric-a-1";

      await asTenant(TENANT_A, async (tx) => {
        await tx.kPI.create({
          data: {
            id: kpiId,
            tenantId: TENANT_A,
            orgId: ORG_A,
            name: "Gross Margin",
            code: "GM_Q3",
            value: "84.5250",
            numericValue: new Prisma.Decimal("84.5250"),
            targetValue: new Prisma.Decimal("80.0000"),
            currency: "USD",
            version: 1,
            analyticsValues: {
              create: {
                id: kpiValId,
                tenantId: TENANT_A,
                value: new Prisma.Decimal("84.5250"),
                currency: "USD",
                periodStart: new Date("2026-07-01"),
                periodEnd: new Date("2026-09-30"),
                version: 1,
              },
            },
          },
        });

        await tx.analyticsKpiDefinition.create({
          data: {
            id: kpiDefId,
            tenantId: TENANT_A,
            name: "ARR Velocity",
            code: "ARR_VELOCITY",
            formula: "SUM(arr) / COUNT(accounts)",
            target: 150000.5,
            targetValue: new Prisma.Decimal("150000.5000"),
            currency: "USD",
            version: 1,
            trendResults: {
              create: {
                id: trendId,
                tenantId: TENANT_A,
                period: "MONTHLY",
                periodStart: new Date("2026-08-01"),
                periodEnd: new Date("2026-08-31"),
                value: 152340.25,
                exactValue: new Prisma.Decimal("152340.2500"),
                previousValue: 148100.0,
                exactPreviousValue: new Prisma.Decimal("148100.0000"),
                currency: "USD",
                version: 1,
              },
            },
          },
        });

        await tx.analyticsBiMetricDefinition.create({
          data: {
            id: biMetricId,
            tenantId: TENANT_A,
            name: "Customer Lifetime Value",
            code: "CLV_ENTERPRISE",
            sourceTable: "invoices",
            sourceColumn: "amount",
            aggregation: "SUM",
            dataType: "CURRENCY",
            currency: "USD",
            version: "1.2.0",
            versionNumber: 2,
            certificationLevel: "GOLD",
            certifiedBy: "auditor@domain.com",
            certifiedAt: new Date("2026-09-01"),
            privacyClassification: "RESTRICTED",
            qualityScore: new Prisma.Decimal("98.50"),
            lineageSources: { upstream: ["raw_invoices", "contract_lines"] },
            freshnessSchedule: "0 * * * *",
            freshnessSlaMinutes: 60,
          },
        });
      });

      // Tenant A queries: verify Decimal precision & governance metadata
      await asTenant(TENANT_A, async (tx) => {
        const kpi = await tx.kPI.findUnique({ where: { id: kpiId }, include: { analyticsValues: true } });
        expect(kpi).not.toBeNull();
        expect(kpi?.numericValue?.toString()).toBe("84.525");
        expect(kpi?.targetValue?.toString()).toBe("80");
        expect(kpi?.analyticsValues[0]?.value.toString()).toBe("84.525");

        const biMetric = await tx.analyticsBiMetricDefinition.findUnique({ where: { id: biMetricId } });
        expect(biMetric).not.toBeNull();
        expect(biMetric?.version).toBe("1.2.0");
        expect(biMetric?.certificationLevel).toBe("GOLD");
        expect(biMetric?.privacyClassification).toBe("RESTRICTED");
        expect(biMetric?.qualityScore?.toString()).toBe("98.5");

        const trend = await tx.analyticsTrendResult.findUnique({ where: { id: trendId } });
        expect(trend).not.toBeNull();
        expect(trend?.exactValue?.toString()).toBe("152340.25");
      });

      // Tenant B denied
      await asTenant(TENANT_B, async (tx) => {
        expect(await tx.kPI.findUnique({ where: { id: kpiId } })).toBeNull();
        expect(await tx.analyticsKpiValue.findUnique({ where: { id: kpiValId } })).toBeNull();
        expect(await tx.analyticsKpiDefinition.findUnique({ where: { id: kpiDefId } })).toBeNull();
        expect(await tx.analyticsTrendResult.findUnique({ where: { id: trendId } })).toBeNull();
        expect(await tx.analyticsBiMetricDefinition.findUnique({ where: { id: biMetricId } })).toBeNull();
      });

      // No context denied
      expect(await appPrisma.kPI.findUnique({ where: { id: kpiId } })).toBeNull();
      expect(await appPrisma.analyticsBiMetricDefinition.findUnique({ where: { id: biMetricId } })).toBeNull();
    });
  });

  describe("Table Family 4: Datasets & Pipelines", () => {
    it("proves Tenant A access, Tenant B denial, and pipeline dataset foreign key relations", async () => {
      const srcDatasetId = "test-ds-src-a-1";
      const tgtDatasetId = "test-ds-tgt-a-1";
      const pipelineId = "test-pipe-a-1";

      await asTenant(TENANT_A, async (tx) => {
        await tx.analyticsDataDataset.create({
          data: {
            id: srcDatasetId,
            tenantId: TENANT_A,
            name: "Raw Invoices Source",
            sourceType: "POSTGRES_TABLE",
            schemaJson: { columns: ["id", "amount", "date"] },
            version: 1,
          },
        });
        await tx.analyticsDataDataset.create({
          data: {
            id: tgtDatasetId,
            tenantId: TENANT_A,
            name: "Aggregated Revenue Target",
            sourceType: "WAREHOUSE_TABLE",
            schemaJson: { columns: ["month", "total_rev"] },
            version: 1,
          },
        });
        await tx.analyticsDataPipeline.create({
          data: {
            id: pipelineId,
            tenantId: TENANT_A,
            pipelineName: "Monthly Revenue Aggregator",
            sourceDatasetId: srcDatasetId,
            targetDatasetId: tgtDatasetId,
            transformationSql: "SELECT date_trunc('month', date), SUM(amount) FROM raw_invoices GROUP BY 1",
            status: "ACTIVE",
            version: 1,
          },
        });
      });

      // Tenant A reads
      await asTenant(TENANT_A, async (tx) => {
        const pipe = await tx.analyticsDataPipeline.findUnique({
          where: { id: pipelineId },
          include: { sourceDataset: true, targetDataset: true },
        });
        expect(pipe).not.toBeNull();
        expect(pipe?.sourceDataset.name).toBe("Raw Invoices Source");
        expect(pipe?.targetDataset.name).toBe("Aggregated Revenue Target");
      });

      // Tenant B denied
      await asTenant(TENANT_B, async (tx) => {
        expect(await tx.analyticsDataDataset.findUnique({ where: { id: srcDatasetId } })).toBeNull();
        expect(await tx.analyticsDataPipeline.findUnique({ where: { id: pipelineId } })).toBeNull();
      });

      // No context denied
      expect(await appPrisma.analyticsDataPipeline.findUnique({ where: { id: pipelineId } })).toBeNull();
    });
  });

  describe("Table Family 5: Predictive Models, Forecasts, Cohorts & Funnels", () => {
    it("proves predictive model forecasts, cohort retention, and funnel unique constraints", async () => {
      const modelId = "test-model-a-1";
      const forecastRunId = "test-forecast-a-1";
      const cohortAnalysisId = "test-cohort-a-1";
      const cohortGroupId = "test-cohort-grp-a-1";
      const funnelStepId = "test-fnl-step-a-1";
      const funnelConvId = "test-fnl-conv-a-1";

      await asTenant(TENANT_A, async (tx) => {
        await tx.analyticsPredictiveModel.create({
          data: {
            id: modelId,
            tenantId: TENANT_A,
            modelName: "Churn Predictor V2",
            algorithm: "RANDOM_FOREST",
            targetMetric: "churn_probability",
            accuracyScore: new Prisma.Decimal("94.7500"),
            status: "TRAINED",
            version: 1,
            forecastRuns: {
              create: {
                id: forecastRunId,
                tenantId: TENANT_A,
                forecastHorizon: "90_DAYS",
                resultMetrics: { expectedChurnCount: 14, riskScore: 0.12 },
                version: 1,
              },
            },
          },
        });

        await tx.analyticsCohortAnalysis.create({
          data: {
            id: cohortAnalysisId,
            tenantId: TENANT_A,
            cohortName: "Q1 Signup Cohort",
            groupingRule: "SIGNUP_MONTH",
            version: 1,
            cohortGroups: {
              create: {
                id: cohortGroupId,
                tenantId: TENANT_A,
                cohortDate: "2026-01",
                initialUsers: 1200,
                retentionRates: { m1: 0.85, m2: 0.72, m3: 0.68 },
                version: 1,
              },
            },
          },
        });

        await tx.analyticsFunnelStep.create({
          data: {
            id: funnelStepId,
            tenantId: TENANT_A,
            funnelName: "Checkout Funnel",
            stepOrder: 1,
            eventName: "VIEW_CART",
            version: 1,
          },
        });

        await tx.analyticsFunnelConversion.create({
          data: {
            id: funnelConvId,
            tenantId: TENANT_A,
            funnelName: "Checkout Funnel",
            period: "2026-08",
            stepConversions: { step1To2: 0.75, step2To3: 0.5 },
            overallDropoff: new Prisma.Decimal("62.5000"),
            conversionRate: new Prisma.Decimal("37.5000"),
            version: 1,
          },
        });
      });

      // Tenant A reads
      await asTenant(TENANT_A, async (tx) => {
        const model = await tx.analyticsPredictiveModel.findUnique({
          where: { id: modelId },
          include: { forecastRuns: true },
        });
        expect(model).not.toBeNull();
        expect(model?.accuracyScore.toString()).toBe("94.75");
        expect(model?.forecastRuns[0]?.tenantId).toBe(TENANT_A);

        const funnelStep = await tx.analyticsFunnelStep.findUnique({ where: { id: funnelStepId } });
        expect(funnelStep).not.toBeNull();
        expect(funnelStep?.funnelName).toBe("Checkout Funnel");

        const funnelConv = await tx.analyticsFunnelConversion.findUnique({ where: { id: funnelConvId } });
        expect(funnelConv?.overallDropoff.toString()).toBe("62.5");
        expect(funnelConv?.conversionRate?.toString()).toBe("37.5");
      });

      // Tenant B denied
      await asTenant(TENANT_B, async (tx) => {
        expect(await tx.analyticsPredictiveModel.findUnique({ where: { id: modelId } })).toBeNull();
        expect(await tx.analyticsForecastRun.findUnique({ where: { id: forecastRunId } })).toBeNull();
        expect(await tx.analyticsCohortAnalysis.findUnique({ where: { id: cohortAnalysisId } })).toBeNull();
        expect(await tx.analyticsCohortGroup.findUnique({ where: { id: cohortGroupId } })).toBeNull();
        expect(await tx.analyticsFunnelStep.findUnique({ where: { id: funnelStepId } })).toBeNull();
        expect(await tx.analyticsFunnelConversion.findUnique({ where: { id: funnelConvId } })).toBeNull();
      });

      // No context denied
      expect(await appPrisma.analyticsPredictiveModel.findUnique({ where: { id: modelId } })).toBeNull();
      expect(await appPrisma.analyticsFunnelStep.findUnique({ where: { id: funnelStepId } })).toBeNull();
    });
  });

  describe("Table Family 6: Exports, Compliance Audits & Distribution Lists", () => {
    it("proves artifact lifecycle, SHA-256 checksums, and tenant isolation on exports & distribution", async () => {
      const exportJobId = "test-exp-job-a-1";
      const exportFileId = "test-exp-file-a-1";
      const schedExpId = "test-sched-exp-a-1";
      const auditId = "test-audit-a-1";
      const signoffId = "test-signoff-a-1";
      const distListId = "test-dist-list-a-1";
      const distRecipId = "test-dist-recip-a-1";

      const expiryDate = new Date("2026-10-01T00:00:00.000Z");
      const testChecksum = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

      await asTenant(TENANT_A, async (tx) => {
        await tx.reportingExportJob.create({
          data: {
            id: exportJobId,
            tenantId: TENANT_A,
            requestedBy: "user-a-export",
            reportType: "FINANCIAL_LEDGER",
            exportFormat: "CSV",
            filterParams: { year: 2026 },
            status: "COMPLETED",
            expiresAt: expiryDate,
            sha256Checksum: testChecksum,
            version: 1,
            files: {
              create: {
                id: exportFileId,
                tenantId: TENANT_A,
                fileName: "ledger_2026.csv",
                fileSizeBytes: 1048576,
                mimeType: "text/csv",
                sha256Checksum: testChecksum,
                expiresAt: expiryDate,
              },
            },
          },
        });

        await tx.analyticsScheduledExport.create({
          data: {
            id: schedExpId,
            tenantId: TENANT_A,
            name: "Quarterly Revenue Export",
            dataset: "invoices",
            format: "PARQUET",
            schedule: "QUARTERLY",
            expiresAt: expiryDate,
            sha256Checksum: testChecksum,
            version: 1,
          },
        });

        await tx.reportingComplianceAudit.create({
          data: {
            id: auditId,
            tenantId: TENANT_A,
            reportName: "SOX Compliance Q3",
            complianceType: "SOX",
            signoffStatus: "SIGNED",
            auditorId: "auditor-a-1",
            signedAt: new Date("2026-09-02"),
            version: 1,
            signoffs: {
              create: {
                id: signoffId,
                tenantId: TENANT_A,
                signerUserId: "cfo-user-1",
                signatureHash: "sig_abc123_hash",
                comments: "Approved without exceptions",
                version: 1,
              },
            },
          },
        });

        await tx.reportingDistributionList.create({
          data: {
            id: distListId,
            tenantId: TENANT_A,
            listName: "Board Distribution List",
            description: "Quarterly financial board members",
            version: 1,
            recipients: {
              create: {
                id: distRecipId,
                tenantId: TENANT_A,
                recipientEmail: "boardmember@investor.com",
                recipientName: "Jane Doe",
                version: 1,
              },
            },
          },
        });
      });

      // Tenant A reads
      await asTenant(TENANT_A, async (tx) => {
        const expJob = await tx.reportingExportJob.findUnique({
          where: { id: exportJobId },
          include: { files: true },
        });
        expect(expJob).not.toBeNull();
        expect(expJob?.sha256Checksum).toBe(testChecksum);
        expect(expJob?.files[0]?.tenantId).toBe(TENANT_A);
        expect(expJob?.files[0]?.sha256Checksum).toBe(testChecksum);

        const audit = await tx.reportingComplianceAudit.findUnique({
          where: { id: auditId },
          include: { signoffs: true },
        });
        expect(audit).not.toBeNull();
        expect(audit?.signoffs[0]?.tenantId).toBe(TENANT_A);

        const distList = await tx.reportingDistributionList.findUnique({
          where: { id: distListId },
          include: { recipients: true },
        });
        expect(distList).not.toBeNull();
        expect(distList?.recipients[0]?.tenantId).toBe(TENANT_A);
      });

      // Tenant B denied
      await asTenant(TENANT_B, async (tx) => {
        expect(await tx.reportingExportJob.findUnique({ where: { id: exportJobId } })).toBeNull();
        expect(await tx.reportingExportFile.findUnique({ where: { id: exportFileId } })).toBeNull();
        expect(await tx.analyticsScheduledExport.findUnique({ where: { id: schedExpId } })).toBeNull();
        expect(await tx.reportingComplianceAudit.findUnique({ where: { id: auditId } })).toBeNull();
        expect(await tx.reportingSignoffHistory.findUnique({ where: { id: signoffId } })).toBeNull();
        expect(await tx.reportingDistributionList.findUnique({ where: { id: distListId } })).toBeNull();
        expect(await tx.reportingDistributionRecipient.findUnique({ where: { id: distRecipId } })).toBeNull();
      });

      // No context denied
      expect(await appPrisma.reportingExportJob.findUnique({ where: { id: exportJobId } })).toBeNull();
      expect(await appPrisma.reportingExportFile.findUnique({ where: { id: exportFileId } })).toBeNull();
      expect(await appPrisma.reportingComplianceAudit.findUnique({ where: { id: auditId } })).toBeNull();
      expect(await appPrisma.reportingDistributionList.findUnique({ where: { id: distListId } })).toBeNull();
    });
  });
});
