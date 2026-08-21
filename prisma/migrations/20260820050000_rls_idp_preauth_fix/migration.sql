-- Corrects 20260820030000_rls_idp_gap, which broke OIDC login outright.
--
-- WHAT WENT WRONG. That migration applied the standard
-- `tenant_id = current_tenant_id()` policy to three IdP tables. The USING
-- half was fine; the WITH CHECK half was not. `/oidc/authorize` calls
-- `AuthorizationService.issueCode()`, which INSERTs into
-- `oauth_authorization_codes` — and it does so *before any tenant session
-- exists*, because the IdP is the component that establishes tenant identity
-- in the first place. With `current_tenant_id()` NULL, WITH CHECK evaluated
-- false and Postgres rejected the insert; the authorize handler caught the
-- exception and redirected with `error=server_error`. Every OIDC login in
-- the platform failed. Reproduced directly:
--   SELECT set_config('app.current_tenant_id','', false);
--   INSERT INTO oauth_authorization_codes (...) VALUES (...);
--   ERROR: new row violates row-level security policy
--
-- WHY THE OBVIOUS FIXES DON'T APPLY. These tables have an access pattern
-- that tenant-first RLS inverts: the token endpoint looks a row up by its
-- cryptographically random `code_hash`/`token_hash` precisely in order to
-- DISCOVER which tenant it belongs to. Requiring the tenant to be known
-- first is backwards. Threading a tenant session through would mean
-- retrofitting ~54 call sites across the IdP's authentication core,
-- including the ones that cannot have tenant context by construction.
-- `web_domains` has the identical shape and the codebase already resolves it
-- by treating that table as tenant-agnostic (`MODELS_WITHOUT_TENANT`).
--
-- WHAT THIS POLICY DOES AND DOES NOT PROTECT — stated plainly, because a
-- weakened policy that reads like a strong one is worse than none:
--
--   * A caller WITH tenant context sees only its own tenant's rows. This is
--     the risk that actually existed: an authenticated request through the
--     tenant API (`api`, where TenantInterceptor always sets the GUC) can no
--     longer read another tenant's authorization codes, refresh grants or
--     consents. That path is now closed.
--   * A caller WITHOUT tenant context sees all rows. That is the IdP's own
--     pre-authentication flow, and it is the price of keeping login working.
--     Isolation on that path rests on the unguessable hash lookup and on the
--     fact that no tenant-facing API exposes these tables — not on RLS.
--
-- This is a strict improvement over the pre-existing state (RLS entirely
-- disabled, where even tenant-scoped callers could read everything), not a
-- complete solution. Closing the second bullet properly means giving the IdP
-- explicit tenant sessions on its writes plus SECURITY DEFINER accessors for
-- the by-hash lookups — real work, tracked separately, not smuggled into a
-- migration whose job is to un-break authentication.
--
-- `NULLIF(..., '')` because `current_tenant_id()` wraps
-- `current_setting('app.current_tenant_id', TRUE)`, which yields NULL when
-- the GUC was never set but '' when it was explicitly set to empty. Both
-- mean "no tenant context" and both must be admitted.

DROP POLICY IF EXISTS "tenant_isolation_oauth_authorization_codes" ON "oauth_authorization_codes";
CREATE POLICY "tenant_isolation_oauth_authorization_codes" ON "oauth_authorization_codes"
    USING (NULLIF(current_tenant_id(), '') IS NULL OR "tenant_id" = current_tenant_id())
    WITH CHECK (NULLIF(current_tenant_id(), '') IS NULL OR "tenant_id" = current_tenant_id());

DROP POLICY IF EXISTS "tenant_isolation_oauth_refresh_grants" ON "oauth_refresh_grants";
CREATE POLICY "tenant_isolation_oauth_refresh_grants" ON "oauth_refresh_grants"
    USING (NULLIF(current_tenant_id(), '') IS NULL OR "tenant_id" = current_tenant_id())
    WITH CHECK (NULLIF(current_tenant_id(), '') IS NULL OR "tenant_id" = current_tenant_id());

DROP POLICY IF EXISTS "tenant_isolation_oauth_client_consents" ON "oauth_client_consents";
CREATE POLICY "tenant_isolation_oauth_client_consents" ON "oauth_client_consents"
    USING (NULLIF(current_tenant_id(), '') IS NULL OR "tenant_id" = current_tenant_id())
    WITH CHECK (NULLIF(current_tenant_id(), '') IS NULL OR "tenant_id" = current_tenant_id());

-- `platform_grants` is deliberately NOT changed. Its rows are all
-- tenant-agnostic (`tenant_id IS NULL`) and its policy from
-- 20260820030000 already admits them; it was verified working and is not
-- implicated in the login failure.
