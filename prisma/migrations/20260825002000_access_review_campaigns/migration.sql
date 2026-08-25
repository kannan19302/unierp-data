-- Shared PCC-03/OCC-03 access-review lifecycle. Scope is data, not a separate
-- table, so provider and organization reviews retain one auditable state
-- machine and one remediation vocabulary.

CREATE TABLE IF NOT EXISTS "access_review_campaigns" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "scope" TEXT NOT NULL DEFAULT 'ORGANIZATION',
  "name" TEXT NOT NULL,
  "description" TEXT,
  "status" TEXT NOT NULL DEFAULT 'DRAFT',
  "reviewer_strategy" JSONB NOT NULL DEFAULT '{}',
  "starts_at" TIMESTAMP(3),
  "due_at" TIMESTAMP(3),
  "launched_at" TIMESTAMP(3),
  "completed_at" TIMESTAMP(3),
  "created_by" TEXT NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "access_review_campaigns_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "access_review_items" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "campaign_id" TEXT NOT NULL,
  "principal_id" TEXT NOT NULL,
  "role_id" TEXT,
  "access_package_id" TEXT,
  "grant_fingerprint" TEXT NOT NULL,
  "reviewer_id" TEXT,
  "decision" TEXT NOT NULL DEFAULT 'PENDING',
  "decision_reason" TEXT,
  "decided_at" TIMESTAMP(3),
  "remediation_status" TEXT NOT NULL DEFAULT 'NOT_REQUIRED',
  "remediated_at" TIMESTAMP(3),
  "snapshot" JSONB NOT NULL DEFAULT '{}',
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "access_review_items_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "access_review_items_campaign_id_fkey"
    FOREIGN KEY ("campaign_id") REFERENCES "access_review_campaigns"("id")
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS "access_review_decision_history" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "item_id" TEXT NOT NULL,
  "actor_id" TEXT NOT NULL,
  "decision" TEXT NOT NULL,
  "reason" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "access_review_decision_history_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "access_review_decision_history_item_id_fkey"
    FOREIGN KEY ("item_id") REFERENCES "access_review_items"("id")
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS "access_review_items_campaign_id_grant_fingerprint_key"
  ON "access_review_items"("campaign_id", "grant_fingerprint");
CREATE INDEX IF NOT EXISTS "access_review_campaigns_tenant_id_scope_status_idx"
  ON "access_review_campaigns"("tenant_id", "scope", "status");
CREATE INDEX IF NOT EXISTS "access_review_campaigns_tenant_id_due_at_idx"
  ON "access_review_campaigns"("tenant_id", "due_at");
CREATE INDEX IF NOT EXISTS "access_review_items_tenant_id_campaign_id_decision_idx"
  ON "access_review_items"("tenant_id", "campaign_id", "decision");
CREATE INDEX IF NOT EXISTS "access_review_items_tenant_id_principal_id_idx"
  ON "access_review_items"("tenant_id", "principal_id");
CREATE INDEX IF NOT EXISTS "access_review_decision_history_tenant_id_item_id_created_at_idx"
  ON "access_review_decision_history"("tenant_id", "item_id", "created_at");

-- Identity tables are RLS-protected even when reached from a provider route.
-- The provider path establishes its own reserved tenant context; it does not
-- bypass organization isolation.
ALTER TABLE "access_review_campaigns" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "access_review_campaigns" FORCE ROW LEVEL SECURITY;
ALTER TABLE "access_review_items" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "access_review_items" FORCE ROW LEVEL SECURITY;
ALTER TABLE "access_review_decision_history" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "access_review_decision_history" FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "tenant_isolation_access_review_campaigns" ON "access_review_campaigns";
CREATE POLICY "tenant_isolation_access_review_campaigns" ON "access_review_campaigns"
  USING ("tenant_id" = current_tenant_id())
  WITH CHECK ("tenant_id" = current_tenant_id());
DROP POLICY IF EXISTS "tenant_isolation_access_review_items" ON "access_review_items";
CREATE POLICY "tenant_isolation_access_review_items" ON "access_review_items"
  USING ("tenant_id" = current_tenant_id())
  WITH CHECK ("tenant_id" = current_tenant_id());
DROP POLICY IF EXISTS "tenant_isolation_access_review_decision_history" ON "access_review_decision_history";
CREATE POLICY "tenant_isolation_access_review_decision_history" ON "access_review_decision_history"
  USING ("tenant_id" = current_tenant_id())
  WITH CHECK ("tenant_id" = current_tenant_id());
