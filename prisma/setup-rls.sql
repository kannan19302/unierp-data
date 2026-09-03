-- ─────────────────────────────────────────────────────────────────
-- PostgreSQL Row-Level Security (RLS) Setup
-- ─────────────────────────────────────────────────────────────────
-- Run this SQL on the database to enable RLS and tenant isolation.
-- ─────────────────────────────────────────────────────────────────

-- Helper function to extract tenant ID from local transaction setting
CREATE OR REPLACE FUNCTION current_tenant_id() RETURNS VARCHAR AS $$
  SELECT NULLIF(current_setting('app.current_tenant_id', true), '')::VARCHAR;
$$ LANGUAGE sql STABLE;

-- Helper to enable RLS and apply policies to a table
-- Parameters: table_name (text), tenant_col (text)
CREATE OR REPLACE PROCEDURE enable_tenant_rls(table_name text, tenant_col text DEFAULT 'tenant_id') AS $$
BEGIN
  -- Enable RLS and Force it even for table owners
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
  EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY', table_name);
  
  -- Drop existing policy if any
  EXECUTE format('DROP POLICY IF EXISTS tenant_isolation_policy ON public.%I', table_name);
  EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'tenant_isolation_' || table_name, table_name);
  
  -- Create RESTRICTIVE policy for Select/Insert/Update/Delete
  EXECUTE format(
    'CREATE POLICY tenant_isolation_policy ON public.%I USING (%I = current_tenant_id()) WITH CHECK (%I = current_tenant_id())',
    table_name, tenant_col, tenant_col
  );
END;
$$ LANGUAGE plpgsql;

-- Apply RLS universally to all multi-tenant tables in the public schema
DO $$
DECLARE
  r RECORD;
  isolated_count integer := 0;
BEGIN
  FOR r IN (
    SELECT DISTINCT table_name, column_name 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND column_name IN ('tenant_id', 'tenantId')
    ORDER BY table_name
  ) LOOP
    CALL enable_tenant_rls(r.table_name, r.column_name);
    isolated_count := isolated_count + 1;
  END LOOP;
  
  RAISE NOTICE 'Universal RLS applied successfully to % multi-tenant tables.', isolated_count;
END;
$$;
