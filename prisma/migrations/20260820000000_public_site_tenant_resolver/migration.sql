-- Plan phase P0 — bootstraps tenant context for anonymous public-site
-- requests, which today establish NONE at all.
--
-- api/src/developer/builder/web-studio.service.ts `resolveSiteByHost` reads
-- `web_domains` (no tenant_id column, not RLS-protected, correctly readable
-- pre-authentication) `include`-joined into `web_sites` (RLS-protected,
-- FORCE ROW LEVEL SECURITY, `unerp_api` is NOBYPASSRLS). Every downstream
-- call in that request never calls `runWithTenantSession`, so
-- `current_tenant_id()` is NULL for the whole request and RLS's
-- `tenant_id = current_tenant_id()` policy is never true.
--
-- Verified empirically against this dev database before writing this
-- migration: a `web_sites` row visible with the GUC set to its own tenant
-- returns 0 rows the moment the GUC is cleared, `unerp_api` unchanged.
-- That is the CURRENT behaviour of every anonymous public route — the
-- public site feature returns 404/empty for every visitor today, not a
-- cross-tenant leak, only because RLS happens to fail closed under this
-- specific role's NOBYPASSRLS configuration. The fix below makes public
-- serving actually resolve a session explicitly, so it stops depending on
-- that role configuration to be correct at all — a role or connection
-- string changed later (an ops shortcut, a maintenance script run as a
-- superuser) would otherwise turn "broken" into "leaking" with zero code
-- changes.
--
-- Why a function and not a `tenant_id` column on `web_domains`: adding a
-- `tenantId` field to any Prisma model makes
-- `data/scripts/check-rls-verify.mjs` require RLS + FORCE RLS + a policy on
-- that table — by explicit design, with "no exemption list and no
-- allowlist" (see that script's own header, written after a prior incident
-- where 364 tables shipped with RLS silently disabled). `web_domains` must
-- stay readable by host BEFORE any tenant is known, which a normal RLS
-- policy cannot express. A SECURITY DEFINER function sidesteps this
-- correctly: it introduces no new tenant-labelled table for the verifier to
-- reason about, and it exposes only what an unauthenticated visitor could
-- already infer by owning a verified custom domain for a site — site id,
-- tenant id, status. No page content, no collection data, nothing tenant
-- content ever crosses this boundary.
CREATE OR REPLACE FUNCTION resolve_tenant_for_host(p_host text)
RETURNS TABLE(site_id text, tenant_id text, site_status text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT ws.id, ws.tenant_id, ws.status
  FROM web_domains wd
  JOIN web_sites ws ON ws.id = wd.site_id
  WHERE wd.host = p_host
  LIMIT 1;
$$;

-- Owned by whichever role runs this migration (the DB owner, BYPASSRLS) —
-- that is what lets the function body cross the RLS boundary. Callers only
-- get EXECUTE, never direct table access through it.
REVOKE ALL ON FUNCTION resolve_tenant_for_host(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION resolve_tenant_for_host(text) TO unerp_api;
