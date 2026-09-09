-- Deliberately one statement, outside a transaction block, for an existing table.
CREATE UNIQUE INDEX CONCURRENTLY "close_tasks_tenant_id_id_key" ON "close_tasks"("tenant_id", "id");
