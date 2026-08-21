-- Purges self-referential rows from `web_page_migration_conflicts`.
--
-- 20260820110000's conflict query asked only "is this path occupied?", which
-- is true of the page the migration itself moved there. 20260820120000 fixed
-- the query but could not remove rows the old one had already written, and
-- the old query still lives in an applied migration — so anything that
-- replays it (a rebuilt environment, a manual re-run) reintroduces them.
--
-- This makes the report self-correcting: a "conflict" whose occupying page is
-- the very page being migrated is not a conflict, and is deleted here
-- regardless of which query produced it. Idempotent, and safe to re-run.

DELETE FROM "web_page_migration_conflicts" c
 WHERE EXISTS (
   SELECT 1
     FROM "web_site_pages" sp
    WHERE sp.id = c.web_page_id
      AND sp.path = c.attempted_path
 );
