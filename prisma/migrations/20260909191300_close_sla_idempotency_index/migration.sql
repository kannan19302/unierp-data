CREATE UNIQUE INDEX CONCURRENTLY "close_task_slas_tenant_id_idempotency_key_key" ON "close_task_slas"("tenant_id", "idempotency_key");
