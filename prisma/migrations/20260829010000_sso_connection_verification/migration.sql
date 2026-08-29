-- FND-P0-003: a federation connection is inactive until its current
-- configuration passes an explicit connection test. Existing rows are
-- intentionally disabled and require tenant-admin revalidation.
ALTER TABLE "sso_configs"
  ADD COLUMN "verification_status" TEXT NOT NULL DEFAULT 'UNVERIFIED',
  ADD COLUMN "last_verified_at" TIMESTAMP(3),
  ADD COLUMN "last_verified_by" TEXT,
  ADD COLUMN "last_verification_error" TEXT;

ALTER TABLE "sso_configs"
  ADD CONSTRAINT "sso_configs_verification_status_check"
  CHECK ("verification_status" IN ('UNVERIFIED', 'VERIFIED', 'FAILED'));

ALTER TABLE "sso_configs"
  ALTER COLUMN "is_active" SET DEFAULT false;

CREATE INDEX "sso_configs_tenant_id_verification_status_is_active_idx"
  ON "sso_configs"("tenant_id", "verification_status", "is_active");

UPDATE "sso_configs"
SET
  "is_active" = false,
  "verification_status" = 'UNVERIFIED',
  "last_verified_at" = NULL,
  "last_verified_by" = NULL,
  "last_verification_error" = NULL;
