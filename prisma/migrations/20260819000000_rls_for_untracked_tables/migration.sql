-- Row-level security for tenant-scoped tables that reached the database
-- without it.
--
-- These tables were declared in prisma/schema/*.prisma but never had a
-- migration; they were created from a `prisma migrate diff` script, and that
-- generator emits table/index/constraint DDL only — it has no knowledge of the
-- RLS policies this project applies by hand to every tenant-scoped table. They
-- therefore existed with tenant_id columns and NO isolation at all: any tenant
-- context could read and write every other tenant's rows.
--
-- Scope is deliberately narrow. Only tables that actually carry a `tenant_id`
-- are enrolled (18 of the 77); the rest are genuinely global — provider-side
-- catalogues, AI model registries, compliance control definitions — and giving
-- them a tenant predicate would make them permanently invisible instead of
-- secure.
--
-- Shape matches the existing convention exactly (see
-- 20260818010000_w2_platform_entitlement and 20260719060000_oauth_identities):
-- ENABLE + FORCE, with USING and WITH CHECK both bound to current_tenant_id()
-- so a row can be neither read nor written outside its own tenant. FORCE
-- matters because the application role must not be exempt merely by owning
-- the table.

ALTER TABLE "approval_routings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "approval_routings" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_approval_routings" ON "approval_routings";
CREATE POLICY "tenant_isolation_approval_routings" ON "approval_routings"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "budget_policies" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "budget_policies" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_budget_policies" ON "budget_policies";
CREATE POLICY "tenant_isolation_budget_policies" ON "budget_policies"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "catalogue_provisionings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "catalogue_provisionings" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_catalogue_provisionings" ON "catalogue_provisionings";
CREATE POLICY "tenant_isolation_catalogue_provisionings" ON "catalogue_provisionings"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "data_breaches" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "data_breaches" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_data_breaches" ON "data_breaches";
CREATE POLICY "tenant_isolation_data_breaches" ON "data_breaches"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "estate_grants" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "estate_grants" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_estate_grants" ON "estate_grants";
CREATE POLICY "tenant_isolation_estate_grants" ON "estate_grants"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "incidents" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "incidents" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_incidents" ON "incidents";
CREATE POLICY "tenant_isolation_incidents" ON "incidents"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "metering_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "metering_events" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_metering_events" ON "metering_events";
CREATE POLICY "tenant_isolation_metering_events" ON "metering_events"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "org_positions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "org_positions" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_org_positions" ON "org_positions";
CREATE POLICY "tenant_isolation_org_positions" ON "org_positions"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "org_units" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "org_units" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_org_units" ON "org_units";
CREATE POLICY "tenant_isolation_org_units" ON "org_units"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "provider_consumption_reports" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "provider_consumption_reports" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_provider_consumption_reports" ON "provider_consumption_reports";
CREATE POLICY "tenant_isolation_provider_consumption_reports" ON "provider_consumption_reports"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "record_legal_holds" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "record_legal_holds" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_record_legal_holds" ON "record_legal_holds";
CREATE POLICY "tenant_isolation_record_legal_holds" ON "record_legal_holds"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "resource_attributions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "resource_attributions" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_resource_attributions" ON "resource_attributions";
CREATE POLICY "tenant_isolation_resource_attributions" ON "resource_attributions"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "setting_change_approvals" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "setting_change_approvals" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_setting_change_approvals" ON "setting_change_approvals";
CREATE POLICY "tenant_isolation_setting_change_approvals" ON "setting_change_approvals"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "slo_definitions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "slo_definitions" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_slo_definitions" ON "slo_definitions";
CREATE POLICY "tenant_isolation_slo_definitions" ON "slo_definitions"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "sticky_route_assignments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "sticky_route_assignments" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_sticky_route_assignments" ON "sticky_route_assignments";
CREATE POLICY "tenant_isolation_sticky_route_assignments" ON "sticky_route_assignments"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "subject_erasure_keys" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "subject_erasure_keys" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_subject_erasure_keys" ON "subject_erasure_keys";
CREATE POLICY "tenant_isolation_subject_erasure_keys" ON "subject_erasure_keys"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "tenant_feature_overrides" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tenant_feature_overrides" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_tenant_feature_overrides" ON "tenant_feature_overrides";
CREATE POLICY "tenant_isolation_tenant_feature_overrides" ON "tenant_feature_overrides"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "tenant_provider_overrides" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tenant_provider_overrides" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_tenant_provider_overrides" ON "tenant_provider_overrides";
CREATE POLICY "tenant_isolation_tenant_provider_overrides" ON "tenant_provider_overrides"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());
