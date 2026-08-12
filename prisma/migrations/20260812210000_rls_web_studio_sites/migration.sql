-- RLS catch-up for the Studio/Sites tables — F01, D135.
--
-- web.prisma (WebSite, WebSitePage, WebCollection, WebCollectionItem, WebMenu,
-- WebAsset, WebSeo, WebSettings, WebTemplate, WebChatbot, WebFormSubmission,
-- WebOrder, WebToLeadForm) declares a real, tenant-scoped multi-site builder
-- data model — every one of these 14 tables carries a `tenant_id` column. None
-- of them ever had RLS enabled: confirmed by grep across every migration file
-- in this repository for `web_sites`, `web_site_pages`, `web_collections`, and
-- siblings alongside `ENABLE ROW LEVEL SECURITY` or `CREATE POLICY` — zero
-- matches. This is the same class of gap ARCHITECTURE_REVIEW § F5 and the
-- 20260808010000 camelCase catch-up migration both name: a tenant table that
-- shipped with RLS disabled and no policy is a tenant table any session with
-- database access — not just the application's own tenant-scoped middleware —
-- can read or write across every tenant's site content.
--
-- `web_domains` (WebDomain) is deliberately NOT in this list: it has no direct
-- tenant_id column, only siteId — tenancy is derived through WebSite, by
-- design (a domain's ownership follows its site, not a directly duplicated
-- tenant column). `locales` already has RLS from an earlier migration
-- (20260804010000) and is unaffected by this one.
--
-- Idempotent: DROP POLICY IF EXISTS + CREATE POLICY, safe to apply even if a
-- table picked up a policy out of band.

DO $$
DECLARE
  t text;
  tables_to_isolate text[] := ARRAY[
    'web_sites',
    'web_site_pages',
    'web_pages',
    'web_collections',
    'web_collection_items',
    'web_menus',
    'web_assets',
    'web_seo',
    'web_settings',
    'web_templates',
    'web_chatbots',
    'web_form_submissions',
    'web_orders',
    'web_to_lead_forms'
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
        'CREATE POLICY tenant_isolation_%I ON %I USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id())',
        t, t
      );
    ELSE
      RAISE NOTICE 'Studio/Sites RLS catch-up: table % not found — skipping', t;
    END IF;
  END LOOP;
END $$;
