-- Deliberately one statement, outside a transaction block, for an existing table.
CREATE UNIQUE INDEX CONCURRENTLY "close_escalation_rules_tenant_id_id_key" ON "close_escalation_rules"("tenant_id", "id");
