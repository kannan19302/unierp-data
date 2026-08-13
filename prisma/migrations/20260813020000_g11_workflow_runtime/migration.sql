-- G11 — Workflow runtime: builder_workflow_runs and builder_workflow_run_steps
-- (workflow-runtime.prisma).
--
-- The workflow definition lives in builder_workflows (created earlier); these
-- two tables record an execution attempt of that definition. A run carries the
-- overall status (PENDING/RUNNING/WAITING/COMPLETED/FAILED) plus a resume
-- pointer; the run's steps carry the per-node trail (status, input, output,
-- error) in sortOrder, so every run is inspectable step by step and a failed
-- run is resumable from its failing step.
--
-- Both tables get the standard tenant_id + both indexes + RLS treatment, and
-- the migration is hand-authored per the established pattern (see
-- 20260813000000_g09_custom_object_definitions) rather than via `prisma
-- migrate dev`, whose interactive diff against this schema currently proposes
-- dropping live IDP tables it does not know about — filed in 90-DEFECT-LOG.md,
-- out of scope for this migration.

CREATE TABLE "builder_workflow_runs" (
  "id"           TEXT NOT NULL,
  "tenant_id"    TEXT NOT NULL,
  "workflow_id"  TEXT NOT NULL,
  "status"       TEXT NOT NULL DEFAULT 'PENDING',
  "trigger"      TEXT NOT NULL DEFAULT 'MANUAL',
  "input"        JSONB NOT NULL DEFAULT '{}'::jsonb,
  "output"       JSONB NOT NULL DEFAULT '{}'::jsonb,
  "error"        TEXT,
  "resume_from"  TEXT,
  "started_at"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "completed_at" TIMESTAMP(3),
  "created_at"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at"   TIMESTAMP(3) NOT NULL,
  CONSTRAINT "builder_workflow_runs_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "builder_workflow_runs_tenant_id_idx"
  ON "builder_workflow_runs" ("tenant_id");
CREATE INDEX "builder_workflow_runs_workflow_id_tenant_id_idx"
  ON "builder_workflow_runs" ("workflow_id", "tenant_id");

CREATE TABLE "builder_workflow_run_steps" (
  "id"           TEXT NOT NULL,
  "tenant_id"    TEXT NOT NULL,
  "run_id"       TEXT NOT NULL,
  "node_id"      TEXT NOT NULL,
  "node_type"    TEXT NOT NULL,
  "node_label"   TEXT,
  "status"       TEXT NOT NULL DEFAULT 'PENDING',
  "sort_order"   INTEGER NOT NULL,
  "input"        JSONB,
  "output"       JSONB,
  "error"        TEXT,
  "started_at"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "completed_at" TIMESTAMP(3),
  "created_at"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at"   TIMESTAMP(3) NOT NULL,
  CONSTRAINT "builder_workflow_run_steps_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "builder_workflow_run_steps_tenant_id_idx"
  ON "builder_workflow_run_steps" ("tenant_id");
CREATE INDEX "builder_workflow_run_steps_run_id_tenant_id_idx"
  ON "builder_workflow_run_steps" ("run_id", "tenant_id");

ALTER TABLE "builder_workflow_runs"
  ADD CONSTRAINT "builder_workflow_runs_workflow_id_fkey"
  FOREIGN KEY ("workflow_id") REFERENCES "builder_workflows"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "builder_workflow_run_steps"
  ADD CONSTRAINT "builder_workflow_run_steps_run_id_fkey"
  FOREIGN KEY ("run_id") REFERENCES "builder_workflow_runs"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

-- ── RLS: ENABLE + FORCE, so the migrating/seeding owner is not exempt ────────
ALTER TABLE "builder_workflow_runs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "builder_workflow_runs" FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation_builder_workflow_runs"
  ON "builder_workflow_runs"
  USING ("tenant_id" = current_tenant_id())
  WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "builder_workflow_run_steps" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "builder_workflow_run_steps" FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation_builder_workflow_run_steps"
  ON "builder_workflow_run_steps"
  USING ("tenant_id" = current_tenant_id())
  WITH CHECK ("tenant_id" = current_tenant_id());
