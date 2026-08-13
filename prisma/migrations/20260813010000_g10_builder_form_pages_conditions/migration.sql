-- G10 — Form builder: multi-step pages and conditional logic on BuilderForm.
--
-- Purely additive: two nullable-defaulted JSON columns on an existing tenant
-- table. Every existing row gets `[]` for both, so every consumer that reads
-- `fields`/`settings` only (builder-stats/scripting/enterprise services,
-- confirmed via grep before this migration was written) is unaffected.
-- BuilderForm already has RLS from its original migration — this migration
-- adds no new table, so no new RLS grant is needed.

ALTER TABLE "builder_forms" ADD COLUMN "pages" JSONB NOT NULL DEFAULT '[]';
ALTER TABLE "builder_forms" ADD COLUMN "conditions" JSONB NOT NULL DEFAULT '[]';
