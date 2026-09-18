import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const migration = readFileSync(resolve(process.cwd(),
  "prisma/migrations/20260909191200_expand_finance_close_sla_policies/migration.sql"), "utf8");

describe("Finance close SLA expansion migration", () => {
  it("preserves historical task SLA rows and defers reference validation", () => {
    expect(migration).toContain('ADD COLUMN "policy_version_id" TEXT');
    expect(migration).toContain("NOT VALID");
    expect(migration).not.toMatch(/UPDATE\s+"close_task_slas"/i);
    expect(migration).not.toMatch(/DROP\s+(TABLE|COLUMN)/i);
    expect(migration).not.toMatch(/DELETE\s+FROM/i);
  });

  it("enables and forces tenant isolation for every close table in scope", () => {
    const tables = [
      "close_tasks", "close_task_dependencies", "close_task_slas", "close_calendar_events",
      "close_escalation_rules", "close_analytics_snapshots", "close_sla_policies",
      "close_sla_policy_versions", "close_sla_policy_escalations",
    ];
    for (const table of tables) expect(migration).toMatch(new RegExp(`['"]${table}['"]`));
    expect(migration).toContain("ENABLE ROW LEVEL SECURITY");
    expect(migration).toContain("FORCE ROW LEVEL SECURITY");
    expect(migration).toContain("tenant_id = current_tenant_id()");
    expect(migration).toContain("WITH CHECK");
  });

  it("enforces immutable tenant-scoped references and coherent assignment snapshots", () => {
    expect(migration).toContain('FOREIGN KEY ("tenant_id", "task_id")');
    expect(migration).toContain('FOREIGN KEY ("tenant_id", "policy_version_id")');
    expect(migration).toContain('FOREIGN KEY ("tenant_id", "rule_id")');
    expect(migration.match(/ON DELETE RESTRICT ON UPDATE RESTRICT/g)?.length).toBeGreaterThanOrEqual(4);
    expect(migration).toContain('"deadline_at" > "started_at"');
    expect(migration).toContain('"response_deadline_at" <= "deadline_at"');
  });
});
