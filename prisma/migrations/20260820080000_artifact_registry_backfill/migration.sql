-- Plan phase P3 backfill — populate `builder_artifacts` from the concrete
-- artifact tables, then assign ownership from `builder_modules.components`.
--
-- Idempotent: every INSERT is ON CONFLICT DO NOTHING against the
-- (tenant_id, artifact_type, artifact_id) unique index, so re-running this
-- migration (or a later reconciler sweep issuing the same statements) is a
-- no-op for rows already present.
--
-- The per-table INSERTs are written out longhand rather than generated in a
-- loop because the source tables genuinely differ: `builder_forms` has
-- slug/icon/status, `builder_workflows` has status but no slug or icon,
-- `builder_apis`/`builder_themes`/`builder_scripts` have none of the three,
-- and `builder_data_models` has icon but no status. A generic loop would
-- either fail on the missing columns or silently coalesce them wrong; the
-- shapes were read off information_schema before writing this.
--
-- Runs as the migration role, reading across every tenant in one pass. Safe:
-- each row written carries the source row's own tenant_id, so RLS on
-- builder_artifacts is fully intact for every subsequent read.

-- ── 1. Registry rows, one per concrete artifact ──

INSERT INTO "builder_artifacts"
  (id, tenant_id, artifact_type, artifact_id, name, slug, status, icon, created_by, created_at, updated_at)
SELECT gen_random_uuid()::text, tenant_id, 'FORM', id, name, slug, status, icon, created_by, created_at, now()
FROM "builder_forms"
ON CONFLICT (tenant_id, artifact_type, artifact_id) DO NOTHING;

INSERT INTO "builder_artifacts"
  (id, tenant_id, artifact_type, artifact_id, name, slug, status, icon, created_by, created_at, updated_at)
SELECT gen_random_uuid()::text, tenant_id, 'WORKFLOW', id, name, NULL, status, NULL, created_by, created_at, now()
FROM "builder_workflows"
ON CONFLICT (tenant_id, artifact_type, artifact_id) DO NOTHING;

INSERT INTO "builder_artifacts"
  (id, tenant_id, artifact_type, artifact_id, name, slug, status, icon, created_by, created_at, updated_at)
SELECT gen_random_uuid()::text, tenant_id, 'DASHBOARD', id, name, NULL, status, icon, created_by, created_at, now()
FROM "builder_dashboards"
ON CONFLICT (tenant_id, artifact_type, artifact_id) DO NOTHING;

INSERT INTO "builder_artifacts"
  (id, tenant_id, artifact_type, artifact_id, name, slug, status, icon, created_by, created_at, updated_at)
SELECT gen_random_uuid()::text, tenant_id, 'API_ENDPOINT', id, name, NULL, 'DRAFT', NULL, created_by, created_at, now()
FROM "builder_apis"
ON CONFLICT (tenant_id, artifact_type, artifact_id) DO NOTHING;

INSERT INTO "builder_artifacts"
  (id, tenant_id, artifact_type, artifact_id, name, slug, status, icon, created_by, created_at, updated_at)
SELECT gen_random_uuid()::text, tenant_id, 'THEME', id, name, NULL, 'DRAFT', NULL, created_by, created_at, now()
FROM "builder_themes"
ON CONFLICT (tenant_id, artifact_type, artifact_id) DO NOTHING;

INSERT INTO "builder_artifacts"
  (id, tenant_id, artifact_type, artifact_id, name, slug, status, icon, created_by, created_at, updated_at)
SELECT gen_random_uuid()::text, tenant_id, 'SCRIPT', id, name, NULL, 'DRAFT', NULL, created_by, created_at, now()
FROM "builder_scripts"
ON CONFLICT (tenant_id, artifact_type, artifact_id) DO NOTHING;

INSERT INTO "builder_artifacts"
  (id, tenant_id, artifact_type, artifact_id, name, slug, status, icon, created_by, created_at, updated_at)
SELECT gen_random_uuid()::text, tenant_id, 'DATA_OBJECT', id, name, NULL, 'DRAFT', icon, created_by, created_at, now()
FROM "builder_data_models"
ON CONFLICT (tenant_id, artifact_type, artifact_id) DO NOTHING;

-- ── 2. Ownership, derived from builder_modules.components ──
--
-- `components` is [{id, type:'form'|'workflow'|'dashboard'|'automation',
-- refId, name}]. Anything NOT referenced by any module keeps
-- owner_project_id = NULL and therefore lands in the Library. That is the
-- correct semantic and it is also what makes the Library non-empty on day
-- one instead of a feature nobody discovers.
--
-- 'automation' is mapped to WORKFLOW: it is the same underlying
-- builder_workflows row, listed under a different label in the module UI.

UPDATE "builder_artifacts" a
SET owner_project_id = p.id, updated_at = now()
FROM "builder_modules" m
JOIN "dev_projects" p ON p.app_id = m.id
CROSS JOIN LATERAL jsonb_array_elements(
    CASE jsonb_typeof(m.components) WHEN 'array' THEN m.components ELSE '[]'::jsonb END
) AS c(elem)
WHERE a.tenant_id = m.tenant_id
  AND a.artifact_id = (c.elem ->> 'refId')
  AND a.artifact_type = CASE lower(c.elem ->> 'type')
        WHEN 'form'       THEN 'FORM'
        WHEN 'workflow'   THEN 'WORKFLOW'
        WHEN 'automation' THEN 'WORKFLOW'
        WHEN 'dashboard'  THEN 'DASHBOARD'
        ELSE NULL
      END
  AND a.owner_project_id IS NULL;

-- ── 3. Mirror every owned artifact into the attachment table ──
--
-- `is_owner = true` so "everything visible inside project X" is one query
-- against builder_artifact_attachments, rather than a union of "owned by X"
-- and "attached to X".

INSERT INTO "builder_artifact_attachments"
  (id, tenant_id, artifact_id, project_id, is_owner, attached_at)
SELECT gen_random_uuid()::text, a.tenant_id, a.id, a.owner_project_id, true, now()
FROM "builder_artifacts" a
WHERE a.owner_project_id IS NOT NULL
ON CONFLICT (artifact_id, project_id) DO NOTHING;
