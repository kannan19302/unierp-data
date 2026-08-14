-- G13 Rules and decision engine — RLS for rules engine tables
-- Enable RLS and create tenant_isolation policies for decision_tables,
-- decision_table_rules, rule_sets, rule_definitions, rule_evaluation_logs.
-- These tables were created after the bulk RLS migration (20260718101000)
-- and the camelCase catch-up (20260808010000), so they need explicit policies.
--
-- Idempotent: ALTER TABLE ... ENABLE/FORCE RLS is idempotent;
-- DROP POLICY IF EXISTS + CREATE POLICY handles re-runs.

DO $g13_rls$
DECLARE
  tbl TEXT;
BEGIN
  FOR tbl IN
    SELECT unnest(ARRAY[
      'decision_tables',
      'decision_table_rules',
      'rule_sets',
      'rule_definitions',
      'rule_evaluation_logs'
    ])
  LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = tbl
    ) THEN
      EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', tbl);
      EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', tbl);
      EXECUTE format('DROP POLICY IF EXISTS tenant_isolation_%I ON %I', tbl, tbl);
      EXECUTE format(
        'CREATE POLICY tenant_isolation_%I ON %I USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id())',
        tbl, tbl
      );
    ELSE
      RAISE NOTICE 'G13 RLS: table % not found — skipping', tbl;
    END IF;
  END LOOP;
END;
$g13_rls$;