-- Enterprise platform catalog and policy-decision contract.
-- Discovery metadata is deliberately separate from authorization grants: a
-- public tile may be visible while launch remains denied, and hidden UI never
-- substitutes for enforcement at /oidc/authorize.

ALTER TABLE "platforms"
  ADD COLUMN IF NOT EXISTS "lifecycle" TEXT NOT NULL DEFAULT 'ACTIVE',
  ADD COLUMN IF NOT EXISTS "surface_type" TEXT NOT NULL DEFAULT 'USER_UI',
  ADD COLUMN IF NOT EXISTS "is_user_facing" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS "discoverability" TEXT NOT NULL DEFAULT 'ENTITLED',
  ADD COLUMN IF NOT EXISTS "category" TEXT NOT NULL DEFAULT 'WORK',
  ADD COLUMN IF NOT EXISTS "sort_weight" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "minimum_assurance" TEXT;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'platforms_lifecycle_check') THEN
    ALTER TABLE "platforms" ADD CONSTRAINT "platforms_lifecycle_check"
      CHECK ("lifecycle" IN ('ACTIVE', 'MAINTENANCE', 'SUSPENDED', 'RETIRED'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'platforms_surface_type_check') THEN
    ALTER TABLE "platforms" ADD CONSTRAINT "platforms_surface_type_check"
      CHECK ("surface_type" IN ('USER_UI', 'NATIVE_CLIENT', 'SERVICE', 'OPERATIONS'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'platforms_discoverability_check') THEN
    ALTER TABLE "platforms" ADD CONSTRAINT "platforms_discoverability_check"
      CHECK ("discoverability" IN ('PUBLIC', 'ENTITLED', 'INTERNAL'));
  END IF;
END $$;

ALTER TABLE "platform_grants"
  ADD COLUMN IF NOT EXISTS "effect" TEXT NOT NULL DEFAULT 'ALLOW',
  ADD COLUMN IF NOT EXISTS "valid_from" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "valid_until" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "conditions" JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS "reason" TEXT,
  ADD COLUMN IF NOT EXISTS "created_by" TEXT,
  ADD COLUMN IF NOT EXISTS "review_at" TIMESTAMP(3);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'platform_grants_effect_check') THEN
    ALTER TABLE "platform_grants" ADD CONSTRAINT "platform_grants_effect_check"
      CHECK ("effect" IN ('ALLOW', 'DENY'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'platform_grants_valid_window_check') THEN
    ALTER TABLE "platform_grants" ADD CONSTRAINT "platform_grants_valid_window_check"
      CHECK ("valid_from" IS NULL OR "valid_until" IS NULL OR "valid_from" < "valid_until");
  END IF;
END $$;

-- GROUP is resolved from authoritative group membership, not a client-provided
-- label. USER continues to require tenant scope.
ALTER TABLE "platform_grants" DROP CONSTRAINT IF EXISTS "platform_grants_subject_type_check";
ALTER TABLE "platform_grants" ADD CONSTRAINT "platform_grants_subject_type_check"
  CHECK ("subject_type" IN ('ROLE', 'PLAN', 'USER', 'GROUP'));

CREATE INDEX IF NOT EXISTS "platform_grants_policy_lookup_idx"
  ON "platform_grants" ("platform_code", "tenant_id", "subject_type", "subject_id", "effect");
CREATE INDEX IF NOT EXISTS "platforms_wizard_order_idx"
  ON "platforms" ("is_user_facing", "lifecycle", "sort_weight", "code");
