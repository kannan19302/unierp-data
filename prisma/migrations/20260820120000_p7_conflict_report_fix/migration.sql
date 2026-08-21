-- Corrects the conflict reporting in 20260820110000_p7_web_pages_to_site_pages.
--
-- That migration's conflict INSERT asked "does a page already exist at this
-- path?" — which is true of a page THIS migration itself created on a
-- previous run. So re-running it reported every already-migrated page as a
-- fresh collision (observed: 1 real conflict became 4 after one re-run), and
-- because each row got a new uuid, `ON CONFLICT DO NOTHING` had nothing to
-- match and duplicated them.
--
-- Two fixes: only count it a conflict when the occupying page is a DIFFERENT
-- row (`sp.id <> wp.id` — the migration preserves ids, so a page it already
-- moved occupies its own path), and give the report table a real unique key
-- so a re-run updates rather than duplicates.

DELETE FROM "web_page_migration_conflicts" a
 USING "web_page_migration_conflicts" b
 WHERE a.ctid < b.ctid AND a.web_page_id = b.web_page_id;

ALTER TABLE "web_page_migration_conflicts"
  DROP CONSTRAINT IF EXISTS "web_page_migration_conflicts_web_page_id_key";
ALTER TABLE "web_page_migration_conflicts"
  ADD CONSTRAINT "web_page_migration_conflicts_web_page_id_key" UNIQUE ("web_page_id");

-- Re-run the corrected report. Idempotent in both senses now: it will not
-- duplicate, and it will not invent conflicts for its own prior output.
INSERT INTO "web_page_migration_conflicts" (id, tenant_id, web_page_id, slug, attempted_path, reason)
SELECT gen_random_uuid()::text, wp.tenant_id, wp.id, wp.slug,
       CASE WHEN wp.slug IN ('', 'home', 'index') THEN '/' ELSE '/' || wp.slug END,
       'A different page already occupies this path on the default site'
FROM "web_pages" wp
JOIN "web_sites" ws ON ws.tenant_id = wp.tenant_id AND ws.slug = 'default'
WHERE EXISTS (
  SELECT 1 FROM "web_site_pages" sp
   WHERE sp.site_id = ws.id
     AND sp.path = CASE WHEN wp.slug IN ('', 'home', 'index') THEN '/' ELSE '/' || wp.slug END
     AND sp.id <> wp.id
)
ON CONFLICT ("web_page_id") DO NOTHING;
