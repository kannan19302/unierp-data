-- Verified Account Center contact channels. Primary email rows are backfilled
-- from the existing user authority; recovery addresses remain unverified until
-- their one-time, hashed token is consumed.

CREATE TABLE IF NOT EXISTS "account_contacts" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "type" TEXT NOT NULL DEFAULT 'EMAIL',
  "value" TEXT NOT NULL,
  "normalized_value" TEXT NOT NULL,
  "label" TEXT NOT NULL DEFAULT 'Recovery email',
  "is_primary" BOOLEAN NOT NULL DEFAULT false,
  "verified_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "account_contacts_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "account_contacts_tenant_user_id_key" UNIQUE ("tenant_id", "user_id", "id"),
  CONSTRAINT "account_contacts_tenant_user_fkey"
    FOREIGN KEY ("tenant_id", "user_id") REFERENCES "users" ("tenant_id", "id")
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS "account_contact_verifications" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "contact_id" TEXT NOT NULL,
  "token_hash" TEXT NOT NULL,
  "expires_at" TIMESTAMP(3) NOT NULL,
  "used_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "account_contact_verifications_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "account_contact_verifications_contact_fkey"
    FOREIGN KEY ("tenant_id", "user_id", "contact_id")
    REFERENCES "account_contacts" ("tenant_id", "user_id", "id")
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS "account_contacts_tenant_type_value_key"
  ON "account_contacts" ("tenant_id", "type", "normalized_value");
CREATE INDEX IF NOT EXISTS "account_contacts_tenant_user_idx"
  ON "account_contacts" ("tenant_id", "user_id");
CREATE UNIQUE INDEX IF NOT EXISTS "account_contact_verifications_token_hash_key"
  ON "account_contact_verifications" ("token_hash");
CREATE INDEX IF NOT EXISTS "account_contact_verifications_owner_idx"
  ON "account_contact_verifications" ("tenant_id", "user_id", "contact_id");
CREATE INDEX IF NOT EXISTS "account_contact_verifications_expires_idx"
  ON "account_contact_verifications" ("expires_at");

INSERT INTO "account_contacts" (
  "id", "tenant_id", "user_id", "type", "value", "normalized_value",
  "label", "is_primary", "verified_at", "created_at", "updated_at"
)
SELECT 'primary-' || md5(u."tenant_id" || ':' || u."id" || ':' || lower(btrim(u."email"))),
       u."tenant_id", u."id", 'EMAIL', u."email", lower(btrim(u."email")),
       'Primary email', true, u."email_verified_at", u."created_at", CURRENT_TIMESTAMP
FROM "users" u
ON CONFLICT ("tenant_id", "type", "normalized_value") DO NOTHING;

ALTER TABLE "account_contacts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "account_contacts" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_account_contacts" ON "account_contacts";
CREATE POLICY "tenant_isolation_account_contacts" ON "account_contacts"
  USING ("tenant_id" = current_tenant_id())
  WITH CHECK ("tenant_id" = current_tenant_id());

ALTER TABLE "account_contact_verifications" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "account_contact_verifications" FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tenant_isolation_account_contact_verifications" ON "account_contact_verifications";
CREATE POLICY "tenant_isolation_account_contact_verifications" ON "account_contact_verifications"
  USING ("tenant_id" = current_tenant_id())
  WITH CHECK ("tenant_id" = current_tenant_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON "account_contacts" TO unerp_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON "account_contact_verifications" TO unerp_api;

-- Email verification begins before an authenticated tenant context exists.
-- Consume one exact high-entropy token atomically and return only identifiers;
-- the service re-enters tenant RLS for every subsequent operation.
CREATE OR REPLACE FUNCTION auth_consume_account_contact_verification(p_token_hash TEXT)
RETURNS TABLE(tenant_id TEXT, user_id TEXT, contact_id TEXT)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  consumed RECORD;
BEGIN
  UPDATE account_contact_verifications
  SET used_at = CURRENT_TIMESTAMP
  WHERE token_hash = p_token_hash
    AND used_at IS NULL
    AND expires_at > CURRENT_TIMESTAMP
  RETURNING account_contact_verifications.tenant_id,
            account_contact_verifications.user_id,
            account_contact_verifications.contact_id
  INTO consumed;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  UPDATE account_contacts
  SET verified_at = COALESCE(verified_at, CURRENT_TIMESTAMP),
      updated_at = CURRENT_TIMESTAMP
  WHERE id = consumed.contact_id
    AND account_contacts.tenant_id = consumed.tenant_id
    AND account_contacts.user_id = consumed.user_id;

  RETURN QUERY SELECT consumed.tenant_id, consumed.user_id, consumed.contact_id;
END;
$$;

REVOKE ALL ON FUNCTION auth_consume_account_contact_verification(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth_consume_account_contact_verification(TEXT) TO unerp_api;
