-- Expand only. Existing task deadlines and unknown policy provenance are preserved.
BEGIN;

CREATE TABLE "close_sla_policies" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "tenant_id" TEXT NOT NULL,
  "current_version" INTEGER NOT NULL DEFAULT 1 CHECK ("current_version" > 0),
  "status" TEXT NOT NULL DEFAULT 'ACTIVE' CHECK ("status" IN ('ACTIVE', 'RETIRED')),
  "created_by" TEXT NOT NULL,
  "updated_by" TEXT NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL
);
CREATE UNIQUE INDEX "close_sla_policies_tenant_id_id_key" ON "close_sla_policies"("tenant_id", "id");
CREATE INDEX "close_sla_policies_tenant_id_status_idx" ON "close_sla_policies"("tenant_id", "status");

CREATE TABLE "close_sla_policy_versions" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "tenant_id" TEXT NOT NULL,
  "policy_id" TEXT NOT NULL,
  "version" INTEGER NOT NULL CHECK ("version" > 0),
  "name" TEXT NOT NULL,
  "description" TEXT,
  "task_type" TEXT NOT NULL,
  "priority" TEXT NOT NULL,
  "time_basis" TEXT NOT NULL DEFAULT 'ELAPSED' CHECK ("time_basis" = 'ELAPSED'),
  "response_time_ms" BIGINT NOT NULL CHECK ("response_time_ms" > 0),
  "resolution_time_ms" BIGINT NOT NULL CHECK ("resolution_time_ms" >= "response_time_ms" AND "resolution_time_ms" <= 3155760000000),
  "created_by" TEXT NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "close_sla_policy_versions_tenant_id_policy_id_fkey"
    FOREIGN KEY ("tenant_id", "policy_id") REFERENCES "close_sla_policies"("tenant_id", "id") ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE UNIQUE INDEX "close_sla_policy_versions_tenant_id_id_key" ON "close_sla_policy_versions"("tenant_id", "id");
CREATE UNIQUE INDEX "close_sla_policy_versions_tenant_id_policy_id_version_key" ON "close_sla_policy_versions"("tenant_id", "policy_id", "version");

CREATE TABLE "close_sla_policy_escalations" (
  "tenant_id" TEXT NOT NULL,
  "policy_version_id" TEXT NOT NULL,
  "rule_id" TEXT NOT NULL,
  PRIMARY KEY ("tenant_id", "policy_version_id", "rule_id"),
  CONSTRAINT "close_sla_policy_escalations_tenant_id_policy_version_id_fkey"
    FOREIGN KEY ("tenant_id", "policy_version_id") REFERENCES "close_sla_policy_versions"("tenant_id", "id") ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT "close_sla_policy_escalations_tenant_id_rule_id_fkey"
    FOREIGN KEY ("tenant_id", "rule_id") REFERENCES "close_escalation_rules"("tenant_id", "id") ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE INDEX "close_sla_policy_escalations_tenant_id_rule_id_idx" ON "close_sla_policy_escalations"("tenant_id", "rule_id");

ALTER TABLE "close_task_slas"
  ADD COLUMN "policy_version_id" TEXT,
  ADD COLUMN "started_at" TIMESTAMP(3),
  ADD COLUMN "response_deadline_at" TIMESTAMP(3),
  ADD COLUMN "response_time_ms" BIGINT,
  ADD COLUMN "resolution_time_ms" BIGINT,
  ADD COLUMN "idempotency_key" TEXT,
  ADD COLUMN "assignment_fingerprint" TEXT,
  ADD CONSTRAINT "close_task_slas_tenant_id_policy_version_id_fkey"
    FOREIGN KEY ("tenant_id", "policy_version_id") REFERENCES "close_sla_policy_versions"("tenant_id", "id") ON DELETE RESTRICT ON UPDATE RESTRICT NOT VALID,
  ADD CONSTRAINT "close_task_slas_tenant_id_task_id_fkey"
    FOREIGN KEY ("tenant_id", "task_id") REFERENCES "close_tasks"("tenant_id", "id") ON DELETE RESTRICT ON UPDATE RESTRICT NOT VALID;

-- The new fields stay null for legacy rows. New assignments must provide a coherent snapshot.
ALTER TABLE "close_task_slas" ADD CONSTRAINT "close_task_slas_assignment_snapshot_check" CHECK (
  ("started_at" IS NULL AND "idempotency_key" IS NULL AND "assignment_fingerprint" IS NULL
    AND "policy_version_id" IS NULL AND "response_deadline_at" IS NULL
    AND "response_time_ms" IS NULL AND "resolution_time_ms" IS NULL)
  OR
  ("started_at" IS NOT NULL AND "idempotency_key" IS NOT NULL AND "assignment_fingerprint" IS NOT NULL
    AND "deadline_at" > "started_at"
    AND "resolution_time_ms" IS NOT NULL AND "resolution_time_ms" > 0 AND "resolution_time_ms" <= 3155760000000
    AND (("response_deadline_at" IS NULL AND "response_time_ms" IS NULL)
      OR ("response_deadline_at" IS NOT NULL AND "response_time_ms" IS NOT NULL
        AND "response_deadline_at" > "started_at" AND "response_deadline_at" <= "deadline_at"
        AND "response_time_ms" > 0 AND "response_time_ms" <= "resolution_time_ms")))
) NOT VALID;

DO $rls$
DECLARE target_table TEXT;
BEGIN
  -- Close the isolation gap for close tables created by the August 4 schema import,
  -- after the July bulk-RLS sweep. Reapplying the canonical policy is idempotent.
  FOREACH target_table IN ARRAY ARRAY[
    'close_tasks', 'close_task_dependencies', 'close_task_slas', 'close_calendar_events',
    'close_escalation_rules', 'close_analytics_snapshots'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', target_table);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', target_table);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'tenant_isolation_' || target_table, target_table);
    EXECUTE format('CREATE POLICY %I ON %I USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id())',
      'tenant_isolation_' || target_table, target_table);
  END LOOP;
END;
$rls$;

ALTER TABLE "close_sla_policies" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "close_sla_policies" FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation_close_sla_policies" ON "close_sla_policies"
  USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());

ALTER TABLE "close_sla_policy_versions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "close_sla_policy_versions" FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation_close_sla_policy_versions" ON "close_sla_policy_versions"
  USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());

ALTER TABLE "close_sla_policy_escalations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "close_sla_policy_escalations" FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation_close_sla_policy_escalations" ON "close_sla_policy_escalations"
  USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());

COMMIT;
-- Validate the NOT VALID constraints only after a separate, evidenced historical-reference audit.
