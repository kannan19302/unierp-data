-- Create `auth_api_tokens` — the one tenant-scoped model declared in
-- prisma/idp-schema.prisma that no migration ever created.
--
-- The model (AuthApiToken) has been in the schema since the multi-file split,
-- generating client code, but the table has never been migrated, so it was
-- invisible to every catalogue-based RLS pass and shipped with nothing — no
-- table, no policy. A tenant table that does not exist cannot be protected,
-- but the schema says it should exist, which is itself a gap the schema-derived
-- check must surface. This migration creates it WITH RLS in the same migration,
-- per BACKEND_SCHEMA § 4.4 and the migration-safety rule: a tenant table and its
-- policy land together.

CREATE TABLE "auth_api_tokens" (
    "id"           TEXT      NOT NULL,
    "tenant_id"    TEXT      NOT NULL,
    "user_id"      TEXT      NOT NULL,
    "name"         TEXT      NOT NULL,
    "token_hash"   TEXT      NOT NULL,
    "scopes"       JSONB     NOT NULL DEFAULT '[]',
    "expires_at"   TIMESTAMP(3),
    "last_used_at" TIMESTAMP(3),
    "created_at"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "auth_api_tokens_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "auth_api_tokens_tenant_id_idx" ON "auth_api_tokens"("tenant_id");
CREATE INDEX "auth_api_tokens_user_id_idx" ON "auth_api_tokens"("user_id");
CREATE UNIQUE INDEX "auth_api_tokens_token_hash_key" ON "auth_api_tokens"("token_hash");

ALTER TABLE "auth_api_tokens"
    ADD CONSTRAINT "auth_api_tokens_user_id_fkey" FOREIGN KEY ("user_id")
    REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- The table's own isolation boundary, in the same migration that creates it.
ALTER TABLE "auth_api_tokens" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "auth_api_tokens" FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation_auth_api_tokens" ON "auth_api_tokens"
    USING ("tenant_id" = current_tenant_id())
    WITH CHECK ("tenant_id" = current_tenant_id());
