-- W1 - OIDC provider tables.
--
-- The ten platforms plus the Flutter and desktop clients previously "shared" a
-- session only because browsers ignore port numbers on localhost, and every
-- service held the same HS256 secret. These tables back the authorization-code
-- + PKCE flow that replaces that, with RS256 signing keys held only by the IdP.
--
-- == On row-level security ==================================================
-- BACKEND_SCHEMA 4.4 requires a tenant table and its policy to land in the same
-- migration. These tables deliberately carry NO tenant policy, and the
-- distinction matters:
--
--   * They are authorization-server state, not tenant business data. The
--     tenant_id column records which tenant a grant was issued FOR; it is not
--     an ownership boundary the way it is on, say, invoices.
--   * Every one of them is read and written BEFORE tenant context exists. The
--     /token endpoint looks up an authorization code while the caller is still
--     anonymous - there is no authenticated tenant to scope by yet. Applying
--     current_tenant_id() here would return zero rows for every legitimate
--     exchange, which is precisely the failure already documented at length in
--     api/src/common/guards/jwt-auth.guard.ts, where user_sessions became
--     invisible and the guard rejected every authenticated request.
--
-- The isolation boundary for these tables is that only the IdP service reaches
-- them; api never queries them. That boundary is currently by convention,
-- because compose gives api and idp the same unerp_api role - so a
-- database-level GRANT split would not add protection today. A dedicated
-- unerp_idp role, with these tables revoked from unerp_api, is the correct
-- follow-up and is tracked with the rest of the service split.

-- == Registered relying parties =============================================
CREATE TABLE "oauth_clients" (
    "id"                        TEXT NOT NULL,
    "client_id"                 TEXT NOT NULL,
    "name"                      TEXT NOT NULL,
    "client_secret_hash"        TEXT,
    "client_type"               TEXT NOT NULL DEFAULT 'PUBLIC',
    "platform_code"             TEXT,
    "is_first_party"            BOOLEAN NOT NULL DEFAULT false,
    "owner_tenant_id"           TEXT,
    "redirect_uris"             TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "post_logout_redirect_uris" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "grant_types"               TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "allowed_scopes"            TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "status"                    TEXT NOT NULL DEFAULT 'ACTIVE',
    "created_at"                TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at"                TIMESTAMP(3) NOT NULL,

    CONSTRAINT "oauth_clients_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "oauth_clients_client_id_key" ON "oauth_clients"("client_id");
CREATE INDEX "oauth_clients_owner_tenant_id_idx" ON "oauth_clients"("owner_tenant_id");
CREATE INDEX "oauth_clients_platform_code_idx" ON "oauth_clients"("platform_code");

-- A confidential client without a secret would authenticate on client_id alone.
ALTER TABLE "oauth_clients" ADD CONSTRAINT "oauth_clients_confidential_has_secret"
    CHECK ("client_type" <> 'CONFIDENTIAL' OR "client_secret_hash" IS NOT NULL);

-- == Single-use authorization codes =========================================
CREATE TABLE "oauth_authorization_codes" (
    "id"                    TEXT NOT NULL,
    "code_hash"             TEXT NOT NULL,
    "client_id"             TEXT NOT NULL,
    "user_id"               TEXT NOT NULL,
    "tenant_id"             TEXT NOT NULL,
    "sid"                   TEXT NOT NULL,
    "redirect_uri"          TEXT NOT NULL,
    "scopes"                TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "nonce"                 TEXT,
    "code_challenge"        TEXT NOT NULL,
    "code_challenge_method" TEXT NOT NULL DEFAULT 'S256',
    "expires_at"            TIMESTAMP(3) NOT NULL,
    "consumed_at"           TIMESTAMP(3),
    "created_at"            TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "oauth_authorization_codes_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "oauth_authorization_codes_code_hash_key" ON "oauth_authorization_codes"("code_hash");
CREATE INDEX "oauth_authorization_codes_user_id_idx" ON "oauth_authorization_codes"("user_id");
CREATE INDEX "oauth_authorization_codes_expires_at_idx" ON "oauth_authorization_codes"("expires_at");

-- PKCE is mandatory and S256-only. The "plain" method offers no protection
-- against an attacker who can already observe the authorization request.
ALTER TABLE "oauth_authorization_codes" ADD CONSTRAINT "oauth_authorization_codes_pkce_s256"
    CHECK ("code_challenge_method" = 'S256');

ALTER TABLE "oauth_authorization_codes"
    ADD CONSTRAINT "oauth_authorization_codes_client_id_fkey" FOREIGN KEY ("client_id")
    REFERENCES "oauth_clients"("client_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- == Rotating refresh tokens ================================================
CREATE TABLE "oauth_refresh_grants" (
    "id"              TEXT NOT NULL,
    "token_hash"      TEXT NOT NULL,
    "client_id"       TEXT NOT NULL,
    "user_id"         TEXT NOT NULL,
    "tenant_id"       TEXT NOT NULL,
    "sid"             TEXT NOT NULL,
    "scopes"          TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "expires_at"      TIMESTAMP(3) NOT NULL,
    "revoked_at"      TIMESTAMP(3),
    "rotated_from_id" TEXT,
    "created_at"      TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "oauth_refresh_grants_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "oauth_refresh_grants_token_hash_key" ON "oauth_refresh_grants"("token_hash");
CREATE INDEX "oauth_refresh_grants_user_id_idx" ON "oauth_refresh_grants"("user_id");
CREATE INDEX "oauth_refresh_grants_sid_idx" ON "oauth_refresh_grants"("sid");
CREATE INDEX "oauth_refresh_grants_expires_at_idx" ON "oauth_refresh_grants"("expires_at");

ALTER TABLE "oauth_refresh_grants"
    ADD CONSTRAINT "oauth_refresh_grants_client_id_fkey" FOREIGN KEY ("client_id")
    REFERENCES "oauth_clients"("client_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- == Third-party consent ====================================================
CREATE TABLE "oauth_client_consents" (
    "id"         TEXT NOT NULL,
    "client_id"  TEXT NOT NULL,
    "user_id"    TEXT NOT NULL,
    "tenant_id"  TEXT NOT NULL,
    "scopes"     TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "granted_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revoked_at" TIMESTAMP(3),

    CONSTRAINT "oauth_client_consents_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "oauth_client_consents_client_id_user_id_tenant_id_key"
    ON "oauth_client_consents"("client_id", "user_id", "tenant_id");
CREATE INDEX "oauth_client_consents_user_id_idx" ON "oauth_client_consents"("user_id");

ALTER TABLE "oauth_client_consents"
    ADD CONSTRAINT "oauth_client_consents_client_id_fkey" FOREIGN KEY ("client_id")
    REFERENCES "oauth_clients"("client_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- == RS256 signing keys =====================================================
CREATE TABLE "oidc_signing_keys" (
    "id"                  TEXT NOT NULL,
    "alg"                 TEXT NOT NULL DEFAULT 'RS256',
    "public_jwk"          JSONB NOT NULL,
    "private_key_pem_enc" TEXT NOT NULL,
    "status"              TEXT NOT NULL DEFAULT 'CURRENT',
    "created_at"          TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "retired_at"          TIMESTAMP(3),

    CONSTRAINT "oidc_signing_keys_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "oidc_signing_keys_status_idx" ON "oidc_signing_keys"("status");

-- At most one key may sign new tokens at a time. Two CURRENT keys would make
-- "which key signed this?" ambiguous during a botched rotation.
CREATE UNIQUE INDEX "oidc_signing_keys_one_current"
    ON "oidc_signing_keys"("status") WHERE "status" = 'CURRENT';

-- == Per-IP login throttling ================================================
-- Complements the per-ACCOUNT lockout already on users.failed_login_attempts
-- and users.locked_until, which bounds attempts against one account but does
-- nothing about one origin spraying a password across many accounts.
CREATE TABLE "login_attempt_counters" (
    "id"            TEXT NOT NULL,
    "ip_hash"       TEXT NOT NULL,
    "attempts"      INTEGER NOT NULL DEFAULT 0,
    "locked_until"  TIMESTAMP(3),
    "first_seen_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_seen_at"  TIMESTAMP(3) NOT NULL,

    CONSTRAINT "login_attempt_counters_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "login_attempt_counters_ip_hash_key" ON "login_attempt_counters"("ip_hash");
CREATE INDEX "login_attempt_counters_locked_until_idx" ON "login_attempt_counters"("locked_until");
