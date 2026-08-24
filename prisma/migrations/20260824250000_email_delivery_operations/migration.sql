-- Provider-neutral transactional-email operations: atomic quotas,
-- privacy-minimised delivery events, bounce/complaint suppression and an
-- audited exact-message lookup for unauthenticated provider callbacks.

CREATE TABLE "email_deliveries" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "queue_job_id" TEXT NOT NULL,
  "provider" TEXT NOT NULL,
  "provider_message_id" TEXT NOT NULL,
  "recipient_hash" TEXT NOT NULL,
  "template" TEXT,
  "status" TEXT NOT NULL DEFAULT 'ACCEPTED',
  "is_canary" BOOLEAN NOT NULL DEFAULT false,
  "attempted_providers" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  "accepted_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "last_event_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "email_deliveries_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "email_delivery_events" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "delivery_id" TEXT NOT NULL,
  "provider" TEXT NOT NULL,
  "provider_event_id" TEXT NOT NULL,
  "provider_message_id" TEXT NOT NULL,
  "type" TEXT NOT NULL,
  "reason" TEXT,
  "occurred_at" TIMESTAMP(3) NOT NULL,
  "received_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "email_delivery_events_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "email_delivery_events_delivery_fkey"
    FOREIGN KEY ("delivery_id") REFERENCES "email_deliveries" ("id")
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE "email_suppressions" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "recipient_hash" TEXT NOT NULL,
  "reason" TEXT NOT NULL,
  "source_provider" TEXT NOT NULL,
  "source_event_id" TEXT NOT NULL,
  "active" BOOLEAN NOT NULL DEFAULT true,
  "expires_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "email_suppressions_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "email_usage_daily" (
  "tenant_id" TEXT NOT NULL,
  "usage_date" DATE NOT NULL,
  "reserved_count" INTEGER NOT NULL DEFAULT 0,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "email_usage_daily_pkey" PRIMARY KEY ("tenant_id", "usage_date")
);

CREATE TABLE "email_send_reservations" (
  "tenant_id" TEXT NOT NULL,
  "queue_job_id" TEXT NOT NULL,
  "usage_date" DATE NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "email_send_reservations_pkey" PRIMARY KEY ("tenant_id", "queue_job_id")
);

CREATE UNIQUE INDEX "email_deliveries_provider_message_key"
  ON "email_deliveries" ("provider", "provider_message_id");
CREATE INDEX "email_deliveries_tenant_created_idx"
  ON "email_deliveries" ("tenant_id", "created_at");
CREATE INDEX "email_deliveries_tenant_canary_created_idx"
  ON "email_deliveries" ("tenant_id", "is_canary", "created_at");
CREATE UNIQUE INDEX "email_delivery_events_provider_event_key"
  ON "email_delivery_events" ("provider", "provider_event_id");
CREATE INDEX "email_delivery_events_tenant_occurred_idx"
  ON "email_delivery_events" ("tenant_id", "occurred_at");
CREATE INDEX "email_delivery_events_delivery_occurred_idx"
  ON "email_delivery_events" ("delivery_id", "occurred_at");
CREATE UNIQUE INDEX "email_suppressions_tenant_recipient_key"
  ON "email_suppressions" ("tenant_id", "recipient_hash");
CREATE INDEX "email_suppressions_tenant_active_idx"
  ON "email_suppressions" ("tenant_id", "active");
CREATE INDEX "email_send_reservations_tenant_date_idx"
  ON "email_send_reservations" ("tenant_id", "usage_date");

DO $$
DECLARE table_name TEXT;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'email_deliveries', 'email_delivery_events',
    'email_suppressions', 'email_usage_daily', 'email_send_reservations'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', table_name);
    EXECUTE format(
      'CREATE POLICY %I ON %I USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id())',
      'tenant_isolation_' || table_name,
      table_name
    );
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON %I TO unerp_api', table_name);
  END LOOP;
END $$;

-- One atomic reservation prevents concurrent workers from exceeding the UTC
-- daily quota and refuses an active suppression before a provider sees PII.
CREATE OR REPLACE FUNCTION email_reserve_send(
  p_tenant_id TEXT,
  p_recipient_hash TEXT,
  p_queue_job_id TEXT,
  p_daily_quota INTEGER
) RETURNS TEXT
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE reserved INTEGER;
DECLARE inserted BOOLEAN;
BEGIN
  IF p_daily_quota < 1 THEN
    RETURN 'QUOTA';
  END IF;

  IF EXISTS (
    SELECT 1 FROM email_suppressions
    WHERE tenant_id = p_tenant_id
      AND recipient_hash = p_recipient_hash
      AND active = true
      AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
  ) THEN
    RETURN 'SUPPRESSED';
  END IF;

  INSERT INTO email_send_reservations (tenant_id, queue_job_id, usage_date)
  VALUES (p_tenant_id, p_queue_job_id, CURRENT_DATE)
  ON CONFLICT (tenant_id, queue_job_id) DO NOTHING
  RETURNING true INTO inserted;

  -- The same BullMQ job may be retried after a transient provider/database
  -- failure. Its original reservation remains authoritative and free.
  IF inserted IS NULL THEN
    RETURN 'ALLOWED';
  END IF;

  INSERT INTO email_usage_daily (tenant_id, usage_date, reserved_count)
  VALUES (p_tenant_id, CURRENT_DATE, 1)
  ON CONFLICT (tenant_id, usage_date) DO UPDATE
    SET reserved_count = email_usage_daily.reserved_count + 1,
        updated_at = CURRENT_TIMESTAMP
    WHERE email_usage_daily.reserved_count < p_daily_quota
  RETURNING reserved_count INTO reserved;

  IF reserved IS NULL THEN
    DELETE FROM email_send_reservations
    WHERE tenant_id = p_tenant_id AND queue_job_id = p_queue_job_id;
    RETURN 'QUOTA';
  END IF;
  RETURN 'ALLOWED';
END;
$$;

-- Provider webhooks have no tenant session. Resolve exactly one opaque
-- provider message id and return the minimum identifiers needed to re-enter
-- normal tenant-scoped access.
CREATE OR REPLACE FUNCTION email_lookup_delivery(
  p_provider TEXT,
  p_provider_message_id TEXT
) RETURNS TABLE(tenant_id TEXT, delivery_id TEXT)
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
STABLE
AS $$
  SELECT d.tenant_id, d.id
  FROM email_deliveries d
  WHERE d.provider = lower(p_provider)
    AND d.provider_message_id = p_provider_message_id
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION email_reserve_send(TEXT, TEXT, TEXT, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION email_lookup_delivery(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION email_reserve_send(TEXT, TEXT, TEXT, INTEGER) TO unerp_api;
GRANT EXECUTE ON FUNCTION email_lookup_delivery(TEXT, TEXT) TO unerp_api;
