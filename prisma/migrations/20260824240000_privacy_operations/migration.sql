-- Production privacy operations: resumable erasure execution, legal-hold
-- state, and export-purge evidence. Additive so existing requests remain valid.

ALTER TABLE "data_erasure_requests"
  ADD COLUMN IF NOT EXISTS "execution_started_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "execution_attempts" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "execution_error" TEXT,
  ADD COLUMN IF NOT EXISTS "legal_hold_reason" TEXT;

CREATE INDEX IF NOT EXISTS "data_erasure_requests_status_eligible_at_idx"
  ON "data_erasure_requests" ("status", "eligible_at");

ALTER TABLE "data_export_jobs"
  ADD COLUMN IF NOT EXISTS "purged_at" TIMESTAMP(3);

CREATE INDEX IF NOT EXISTS "data_export_jobs_expiry_idx"
  ON "data_export_jobs" ("status", "expires_at")
  WHERE "expires_at" IS NOT NULL;

-- Cross-tenant workers cannot disable RLS. These narrow claim/purge functions
-- expose only due job identifiers, atomically transition state, and use
-- SKIP LOCKED so multiple replicas cannot execute the same request.
CREATE OR REPLACE FUNCTION privacy_claim_eligible_erasure_requests(p_limit INTEGER DEFAULT 25)
RETURNS TABLE(request_id TEXT, tenant_id TEXT)
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
AS $$
  WITH due AS (
    SELECT id
    FROM data_erasure_requests
    WHERE status IN ('PENDING', 'FAILED')
      AND COALESCE(eligible_at, created_at) <= CURRENT_TIMESTAMP
      AND execution_attempts < 5
    ORDER BY COALESCE(eligible_at, created_at), created_at
    FOR UPDATE SKIP LOCKED
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
  )
  UPDATE data_erasure_requests request
  SET status = 'QUEUED', updated_at = CURRENT_TIMESTAMP
  FROM due
  WHERE request.id = due.id
  RETURNING request.id, request.tenant_id;
$$;

REVOKE ALL ON FUNCTION privacy_claim_eligible_erasure_requests(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION privacy_claim_eligible_erasure_requests(INTEGER) TO unerp_api;

CREATE OR REPLACE FUNCTION privacy_purge_expired_export_jobs(p_limit INTEGER DEFAULT 100)
RETURNS TABLE(job_id TEXT, tenant_id TEXT, file_url TEXT)
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
AS $$
  WITH expired AS (
    SELECT id, file_url
    FROM data_export_jobs
    WHERE expires_at <= CURRENT_TIMESTAMP
      AND purged_at IS NULL
      AND file_url IS NULL
      AND status IN ('COMPLETE', 'FAILED', 'EXPIRED')
    ORDER BY expires_at
    FOR UPDATE SKIP LOCKED
    LIMIT LEAST(GREATEST(p_limit, 1), 500)
  )
  UPDATE data_export_jobs job
  SET status = 'EXPIRED', purged_at = CURRENT_TIMESTAMP, file_url = NULL
  FROM expired
  WHERE job.id = expired.id
  RETURNING job.id, job.tenant_id, expired.file_url;
$$;

REVOKE ALL ON FUNCTION privacy_purge_expired_export_jobs(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION privacy_purge_expired_export_jobs(INTEGER) TO unerp_api;
