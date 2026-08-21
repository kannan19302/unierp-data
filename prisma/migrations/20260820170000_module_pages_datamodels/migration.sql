-- Plan phase P4/P8 — promote `builder_modules.pages` and
-- `builder_modules."dataModels"` out of JSON into real tables, so the P8
-- contract can drop those columns without losing anything.
--
-- `components` needs no equivalent: `builder_artifacts` (P3) already holds
-- it, and the backfill in 20260820080000 already assigned ownership from
-- exactly this JSON.
--
-- Expand + backfill only. The JSON columns stay until P8.

CREATE TABLE "builder_module_pages" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "module_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "type" TEXT NOT NULL DEFAULT 'form',
    "form_id" TEXT,
    "dashboard_id" TEXT,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "builder_module_pages_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "builder_module_pages_module_id_slug_key" ON "builder_module_pages" ("module_id", "slug");
CREATE INDEX "builder_module_pages_tenant_id_module_id_idx" ON "builder_module_pages" ("tenant_id", "module_id");
ALTER TABLE "builder_module_pages" ADD CONSTRAINT "builder_module_pages_module_id_fkey"
    FOREIGN KEY ("module_id") REFERENCES "builder_modules"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "builder_module_data_models" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "module_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "fields" JSONB NOT NULL DEFAULT '[]',
    "relationships" JSONB NOT NULL DEFAULT '[]',
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "builder_module_data_models_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "builder_module_data_models_tenant_id_module_id_idx" ON "builder_module_data_models" ("tenant_id", "module_id");
ALTER TABLE "builder_module_data_models" ADD CONSTRAINT "builder_module_data_models_module_id_fkey"
    FOREIGN KEY ("module_id") REFERENCES "builder_modules"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Backfill. `elem->>'id'` is preserved as the row id where present, so any
-- caller holding a page id from the JSON era keeps working. Idempotent.
INSERT INTO "builder_module_pages"
  (id, tenant_id, module_id, name, slug, type, form_id, dashboard_id, sort_order, created_at, updated_at)
SELECT COALESCE(NULLIF(p.elem ->> 'id', ''), gen_random_uuid()::text),
       m.tenant_id, m.id,
       COALESCE(p.elem ->> 'name', 'Untitled'),
       COALESCE(NULLIF(p.elem ->> 'slug', ''), 'page-' || p.ord::text),
       COALESCE(p.elem ->> 'type', 'form'),
       NULLIF(p.elem ->> 'formId', ''),
       NULLIF(p.elem ->> 'dashboardId', ''),
       p.ord, now(), now()
FROM "builder_modules" m
CROSS JOIN LATERAL jsonb_array_elements(
    CASE jsonb_typeof(m.pages) WHEN 'array' THEN m.pages ELSE '[]'::jsonb END
) WITH ORDINALITY AS p(elem, ord)
ON CONFLICT ("module_id", "slug") DO NOTHING;

INSERT INTO "builder_module_data_models"
  (id, tenant_id, module_id, name, fields, relationships, sort_order, created_at, updated_at)
SELECT COALESCE(NULLIF(d.elem ->> 'id', ''), gen_random_uuid()::text),
       m.tenant_id, m.id,
       COALESCE(d.elem ->> 'name', 'Untitled'),
       COALESCE(d.elem -> 'fields', '[]'::jsonb),
       COALESCE(d.elem -> 'relationships', '[]'::jsonb),
       d.ord, now(), now()
FROM "builder_modules" m
CROSS JOIN LATERAL jsonb_array_elements(
    CASE jsonb_typeof(m."dataModels") WHEN 'array' THEN m."dataModels" ELSE '[]'::jsonb END
) WITH ORDINALITY AS d(elem, ord)
ON CONFLICT ("id") DO NOTHING;
