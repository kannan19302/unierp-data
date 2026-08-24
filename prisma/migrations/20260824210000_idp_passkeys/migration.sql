-- Promote the legacy passkeys table into the tenant-scoped IdP authority.
-- Existing rows are preserved and backfilled from their owning user.

ALTER TABLE "passkeys"
  ADD COLUMN IF NOT EXISTS "tenant_id" TEXT,
  ADD COLUMN IF NOT EXISTS "name" TEXT,
  ADD COLUMN IF NOT EXISTS "device_type" TEXT,
  ADD COLUMN IF NOT EXISTS "backup_eligible" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "backed_up" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "aaguid" TEXT,
  ADD COLUMN IF NOT EXISTS "last_used_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

UPDATE "passkeys" p
SET "tenant_id" = u."tenant_id"
FROM "users" u
WHERE p."user_id" = u."id" AND p."tenant_id" IS NULL;

UPDATE "passkeys"
SET "name" = 'Existing passkey'
WHERE "name" IS NULL OR btrim("name") = '';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM "passkeys" WHERE "tenant_id" IS NULL) THEN
    RAISE EXCEPTION 'Cannot tenant-scope passkeys: an existing row has no owning user';
  END IF;
END $$;

ALTER TABLE "passkeys"
  ALTER COLUMN "tenant_id" SET NOT NULL,
  ALTER COLUMN "name" SET NOT NULL,
  ALTER COLUMN "counter" TYPE BIGINT USING "counter"::BIGINT,
  ALTER COLUMN "counter" SET DEFAULT 0;

CREATE UNIQUE INDEX IF NOT EXISTS "users_tenant_id_id_key"
  ON "users" ("tenant_id", "id");
CREATE INDEX IF NOT EXISTS "passkeys_tenant_id_user_id_idx"
  ON "passkeys" ("tenant_id", "user_id");

ALTER TABLE "passkeys" DROP CONSTRAINT IF EXISTS "passkeys_user_id_fkey";
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'passkeys_tenant_user_fkey'
  ) THEN
    ALTER TABLE "passkeys" ADD CONSTRAINT "passkeys_tenant_user_fkey"
      FOREIGN KEY ("tenant_id", "user_id")
      REFERENCES "users" ("tenant_id", "id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

ALTER TABLE "passkeys" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "passkeys" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_passkeys" ON "passkeys";
CREATE POLICY "tenant_isolation_passkeys" ON "passkeys"
  USING ("tenant_id" = current_tenant_id())
  WITH CHECK ("tenant_id" = current_tenant_id());

-- Passkey-first authentication starts before tenant context exists. This
-- audited exception resolves one exact, high-entropy credential id and returns
-- only verification material; the service immediately re-enters tenant RLS.
CREATE OR REPLACE FUNCTION auth_lookup_passkey(p_credential_id TEXT)
RETURNS TABLE(
  id TEXT,
  tenant_id TEXT,
  user_id TEXT,
  credential_id TEXT,
  public_key TEXT,
  counter BIGINT,
  transports TEXT,
  device_type TEXT,
  backup_eligible BOOLEAN,
  backed_up BOOLEAN
)
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
STABLE
AS $$
  SELECT p.id, p.tenant_id, p.user_id, p.credential_id, p.public_key,
         p.counter, p.transports, p.device_type, p.backup_eligible, p.backed_up
  FROM passkeys p
  JOIN users u ON u.id = p.user_id AND u.tenant_id = p.tenant_id
  WHERE p.credential_id = p_credential_id
    AND u.deleted_at IS NULL
    AND u.status = 'ACTIVE';
$$;

REVOKE ALL ON FUNCTION auth_lookup_passkey(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth_lookup_passkey(TEXT) TO unerp_api;
