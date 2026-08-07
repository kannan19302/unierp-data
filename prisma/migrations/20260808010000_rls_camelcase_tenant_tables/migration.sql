-- RLS catch-up for the 16 tenant tables whose tenant column is `tenantId`.
--
-- These tables carry a camelCase tenant column instead of `tenant_id`. Every
-- bulk-RLS migration and every check — `check-rls-verify.mjs`, the F5 catch-up
-- loop, `tenant-rls-integration.test.ts`, `check-migration-safety.mjs` — matched
-- on `tenant_id` and only `tenant_id`, so a table whose column was named
-- `tenantId` was invisible to all of them and shipped with RLS DISABLED and no
-- policy at all. That is the same class of failure as ARCHITECTURE_REVIEW § F5:
-- a control that cannot see a gap reports clean while a tenant boundary is open.
--
-- The column drift originates in `20260718093000_track_a_reconciliation`, which
-- RENAMED these columns from `tenant_id` to `tenantId` to match their (then)
-- model declarations, and no later pass noticed they had stopped matching the
-- `tenant_id` predicate the whole RLS machinery is written against.
--
-- These 16 tables are the drift survivors: created before the last bulk RLS
-- pass, protected by nothing, and covered by the F5 list's table-name loop only
-- in the sense that the loop never ran against them. Policies must reference the
-- real column, quoted, because `tenantId` would fold to `tenantid` unquoted.
--
-- Idempotent: DROP POLICY IF EXISTS + CREATE POLICY, so it is safe to apply even
-- if a table picked up a policy out of band.

DO $$
DECLARE
  t text;
  tables_to_isolate text[] := ARRAY[
    'asn_discrepancies',
    'cross_dock_events',
    'cross_dock_orders',
    'cross_dock_stations',
    'inventory_cost_adjustments',
    'inventory_cost_layers',
    'inventory_cost_profiles',
    'lot_disposal_records',
    'lot_expiry_alerts',
    'lot_expiry_records',
    'pick_tasks',
    'shipment_exceptions',
    'tenant_lifecycle_events',
    'vmi_agreements',
    'vmi_orders',
    'vmi_stock_snapshots'
  ];
BEGIN
  FOREACH t IN ARRAY tables_to_isolate LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = t
    ) THEN
      EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
      EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
      EXECUTE format('DROP POLICY IF EXISTS tenant_isolation_%I ON %I', t, t);
      EXECUTE format(
        'CREATE POLICY tenant_isolation_%I ON %I USING ("tenantId" = current_tenant_id()) WITH CHECK ("tenantId" = current_tenant_id())',
        t, t
      );
    ELSE
      RAISE NOTICE 'camelCase RLS catch-up: table % not found — skipping', t;
    END IF;
  END LOOP;
END $$;
