-- Account Center governance: subject export ownership/expiry, erasure
-- cooling-off/cancellation, and a narrow verified-identity organization list.

ALTER TABLE "data_export_jobs"
  ADD COLUMN IF NOT EXISTS "requested_by" TEXT,
  ADD COLUMN IF NOT EXISTS "expires_at" TIMESTAMP(3);

ALTER TABLE "data_erasure_requests"
  ADD COLUMN IF NOT EXISTS "request_reason" TEXT,
  ADD COLUMN IF NOT EXISTS "eligible_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "cancelled_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "cancellation_reason" TEXT;

CREATE INDEX IF NOT EXISTS "data_export_jobs_tenant_requested_idx"
  ON "data_export_jobs" ("tenant_id", "requested_by", "created_at" DESC);
CREATE INDEX IF NOT EXISTS "data_erasure_requests_subject_idx"
  ON "data_erasure_requests" ("tenant_id", "requested_by", "created_at" DESC);

-- Organization switching is an authentication concern and begins before the
-- destination tenant context exists. Resolve only active, email-verified user
-- records that share the current verified account email. Ordinary table reads
-- remain protected by forced tenant RLS.
CREATE OR REPLACE FUNCTION auth_list_account_organizations(
  p_user_id TEXT,
  p_tenant_id TEXT
)
RETURNS TABLE(
  target_user_id TEXT,
  tenant_id TEXT,
  tenant_name TEXT,
  tenant_slug TEXT,
  is_current BOOLEAN
)
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
STABLE
AS $$
  WITH source AS (
    SELECT lower(btrim(u.email)) AS normalized_email
    FROM users u
    WHERE u.id = p_user_id
      AND u.tenant_id = p_tenant_id
      AND u.status = 'ACTIVE'
      AND u.deleted_at IS NULL
      AND u.email_verified_at IS NOT NULL
  )
  SELECT target.id,
         target.tenant_id,
         tenant.name,
         tenant.slug,
         target.tenant_id = p_tenant_id
  FROM source
  JOIN users target
    ON lower(btrim(target.email)) = source.normalized_email
   AND target.status = 'ACTIVE'
   AND target.deleted_at IS NULL
   AND target.email_verified_at IS NOT NULL
  JOIN tenants tenant
    ON tenant.id = target.tenant_id
   AND tenant.status = 'ACTIVE'
  ORDER BY (target.tenant_id = p_tenant_id) DESC, lower(tenant.name), tenant.id;
$$;

REVOKE ALL ON FUNCTION auth_list_account_organizations(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth_list_account_organizations(TEXT, TEXT) TO unerp_api;
