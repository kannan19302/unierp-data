-- Row-level security for tenant-scoped tables that reached the database
-- without it. Some early schema snapshots included optional historical tables
-- while clean installs did not. Apply the identical RLS policy only when the
-- table is present, so a clean database is migratable and an upgraded database
-- still receives protection for every table it has.
DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'approval_routings',
    'budget_policies',
    'catalogue_provisionings',
    'data_breaches',
    'estate_grants',
    'incidents',
    'metering_events',
    'org_positions',
    'org_units',
    'provider_consumption_reports',
    'record_legal_holds',
    'resource_attributions',
    'setting_change_approvals',
    'slo_definitions',
    'sticky_route_assignments',
    'subject_erasure_keys',
    'tenant_feature_overrides',
    'tenant_provider_overrides'
  ]
  LOOP
    IF to_regclass(format('public.%I', table_name)) IS NULL THEN
      CONTINUE;
    END IF;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY', table_name);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'tenant_isolation_' || table_name, table_name);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id())',
      'tenant_isolation_' || table_name,
      table_name
    );
  END LOOP;
END $$;
