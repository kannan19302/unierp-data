-- Plan phase P7 — migrate legacy single-site `web_pages` into the multi-site
-- `web_site_pages`, so there is one page model instead of two.
--
-- `web_pages` predates multi-site: it is tenant-scoped with a bare `slug` and
-- a `sections` blob. `web_site_pages` is site-scoped with a `path` and
-- `blocks`. Every legacy page belongs to its tenant's "default" site — the
-- WebSite model's own comment already records that the migrated legacy site
-- is `"default"`.
--
-- Conflicts are REPORTED, not fatal. A legacy slug can collide with a page
-- that already exists at the same path on the default site, and failing the
-- whole migration over one collision would block every tenant for one
-- tenant's data. Skipped rows land in `web_page_migration_conflicts` for a
-- human to resolve, and `web_pages` itself is not touched here — it is
-- dropped in P8, so nothing is lost in the meantime.

CREATE TABLE IF NOT EXISTS "web_page_migration_conflicts" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "web_page_id" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "attempted_path" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "detected_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "web_page_migration_conflicts_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "web_page_migration_conflicts_tenant_id_idx"
    ON "web_page_migration_conflicts" ("tenant_id");

-- Ensure every tenant that has legacy pages has a "default" site to hold
-- them. Idempotent on the (tenant_id, slug) unique key.
INSERT INTO "web_sites" (id, tenant_id, name, slug, status, theme, settings, created_at, updated_at)
SELECT gen_random_uuid()::text, p.tenant_id, 'Default Site', 'default', 'ACTIVE', '{}', '{}', now(), now()
FROM (SELECT DISTINCT tenant_id FROM "web_pages") p
ON CONFLICT (tenant_id, slug) DO NOTHING;

-- Record the collisions BEFORE inserting, so the report reflects what will be
-- skipped rather than what happened to fail.
INSERT INTO "web_page_migration_conflicts" (id, tenant_id, web_page_id, slug, attempted_path, reason)
SELECT gen_random_uuid()::text, wp.tenant_id, wp.id, wp.slug,
       CASE WHEN wp.slug IN ('', 'home', 'index') THEN '/' ELSE '/' || wp.slug END,
       'A page already exists at this path on the default site'
FROM "web_pages" wp
JOIN "web_sites" ws ON ws.tenant_id = wp.tenant_id AND ws.slug = 'default'
WHERE EXISTS (
  SELECT 1 FROM "web_site_pages" sp
   WHERE sp.site_id = ws.id
     AND sp.path = CASE WHEN wp.slug IN ('', 'home', 'index') THEN '/' ELSE '/' || wp.slug END
)
ON CONFLICT DO NOTHING;

-- The migration itself. `home`/`index`/'' map to "/" because that is what the
-- renderer treats as the site root; everything else becomes "/<slug>".
INSERT INTO "web_site_pages"
  (id, site_id, tenant_id, path, title, type, blocks, seo, status, sort_order, created_at, updated_at)
SELECT wp.id, ws.id, wp.tenant_id,
       CASE WHEN wp.slug IN ('', 'home', 'index') THEN '/' ELSE '/' || wp.slug END,
       wp.name,
       'PAGE',
       wp.sections,
       jsonb_build_object('metaTitle', wp.meta_title, 'metaDesc', wp.meta_desc, 'ogImage', wp.og_image),
       wp.status,
       wp.sort_order,
       wp.created_at,
       now()
FROM "web_pages" wp
JOIN "web_sites" ws ON ws.tenant_id = wp.tenant_id AND ws.slug = 'default'
ON CONFLICT (site_id, path) DO NOTHING;
