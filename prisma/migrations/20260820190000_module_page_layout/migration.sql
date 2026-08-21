-- Adds `layout` to builder_module_pages, and backfills it.
--
-- 20260820170000 promoted `builder_modules.pages` out of JSON but omitted
-- `layout` — the page-builder widget array each page carries. Dropping the
-- JSON column in P8 without this would silently lose every app page's
-- layout. Caught while rewriting `addPageToModule`, which reads it.

ALTER TABLE "builder_module_pages" ADD COLUMN IF NOT EXISTS "layout" JSONB NOT NULL DEFAULT '[]';

UPDATE "builder_module_pages" bmp
   SET "layout" = COALESCE(p.elem -> 'layout', '[]'::jsonb)
  FROM "builder_modules" m
  CROSS JOIN LATERAL jsonb_array_elements(
      CASE jsonb_typeof(m.pages) WHEN 'array' THEN m.pages ELSE '[]'::jsonb END
  ) AS p(elem)
 WHERE bmp.module_id = m.id
   AND bmp.id = (p.elem ->> 'id')
   AND p.elem ? 'layout';
