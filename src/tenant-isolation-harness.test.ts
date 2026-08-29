import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { PrismaClient } from "./main-client/index.js";
import {
  assertTenantIsolation,
  listProtectedTables,
  TENANT_A,
  TENANT_B,
} from "./tenant-isolation-harness";

/**
 * Phase J03 — Tenant-isolation test framework.
 *
 * The DoD's "tenant B gets zero rows" test, one line per entity:
 *
 *   assertTenantIsolation({ owner, app, table: t.table, tenantColumn: t.tenantColumn })
 *
 * The catalogue is derived from the live database (every public table carrying
 * a tenant column), so a new tenant table is covered the moment its migration
 * lands — the catalogue cannot go stale.
 *
 * The exit criterion is the second suite in this file: it drops one RLS policy,
 * proves the isolation assertion now FAILS, and restores the policy. A check
 * that cannot fail is D013; this suite exists to prove the harness can.
 */

/** A connection as the application role (unerp_api, NOBYPASSRLS). */
const appRoleUrl =
  process.env.DATABASE_APP_URL ??
  process.env.DATABASE_URL?.replace(
    /\/\/[^:]+:[^@]+@/,
    "//unerp_api:unerp_api_password@",
  );

const owner = new PrismaClient();
const app = appRoleUrl ? new PrismaClient({ datasources: { db: { url: appRoleUrl } } }) : null;

/** Skip cleanly without a database locally, NEVER skip in CI. */
const databaseAvailable = await (async (): Promise<boolean> => {
  try {
    await owner.$queryRaw`SELECT 1`;
    return true;
  } catch (error) {
    if (process.env.CI) {
      throw new Error(
        "Tenant-isolation catalogue requires a database and none was reachable in CI. " +
          `Underlying error: ${(error as Error).message}`,
      );
    }
    console.warn(
      "\n  [skip] Tenant-isolation catalogue — no database reachable.\n" +
        "         Start one with: docker compose -f docker-compose.dev.yml up -d postgres\n",
    );
    return false;
  }
})();

const describeDb = describe.skipIf(!databaseAvailable);

// The catalogue is fetched at module scope (like the DB probe above) because
// `it.each` needs its rows at collection time, before any hook runs.
const catalogue = databaseAvailable ? await listProtectedTables(owner) : [];
const tableRows = catalogue.map((t) => ({
  table: t.table,
  tenantColumn: t.tenantColumn,
}));

afterAll(async () => {
  await app?.$disconnect();
  await owner.$disconnect();
});

describeDb("J03: two-tenant isolation catalogue", () => {
  it("the catalogue is derived from the database and not empty", () => {
    expect(catalogue.length).toBeGreaterThan(0);
    expect(catalogue[0]).toMatchObject({
      table: expect.any(String),
      tenantColumn: expect.stringMatching(/tenant_id|tenantId/),
    });
  });

  it.each(tableRows)(
    "isolates $table (tenant B gets zero rows from tenant A)",
    async ({ table, tenantColumn }) => {
      await assertTenantIsolation({
        owner,
        app: app!,
        table,
        tenantColumn,
      });
    },
  );
});

describeDb("J03: removing an RLS policy makes the isolation test fail", () => {
  const TABLE = "customers";

  it("drops the policy, proves the assertion fails, then restores it", async () => {
    await owner.$executeRawUnsafe(
      `DROP POLICY tenant_isolation_${TABLE} ON "${TABLE}"`,
    );
    try {
      await expect(
        assertTenantIsolation({ owner, app: app!, table: TABLE }),
      ).rejects.toThrow(/no RLS enforcement/);
    } finally {
      await owner.$executeRawUnsafe(
        `CREATE POLICY tenant_isolation_${TABLE} ON "${TABLE}" USING ("tenant_id" = current_tenant_id()) WITH CHECK ("tenant_id" = current_tenant_id())`,
      );
    }
  });

  it("passes again once the policy is restored", async () => {
    await expect(
      assertTenantIsolation({ owner, app: app!, table: TABLE }),
    ).resolves.toBeUndefined();
  });
});

describeDb("J03: harness asserts the app role is NOBYPASSRLS", () => {
  it("fails when the proof connection is a superuser or BYPASSRLS role", async () => {
    // The owner is a superuser, which bypasses RLS — the harness must refuse
    // to certify isolation over such a connection.
    await expect(
      assertTenantIsolation({ owner, app: owner, table: "customers" }),
    ).rejects.toThrow(/NOBYPASSRLS/);
  });
});

describeDb("J03: seed values are unique per tenant", () => {
  it("leaves no trace after a run", async () => {
    // The catalogue suite above seeds and cleans TENANT_A/TENANT_B rows. After
    // it ran, neither tenant should have any rows in a sample table.
    const [row] = await owner.$queryRawUnsafe<Array<{ n: number }>>(
      `SELECT count(*)::int AS n FROM "customers" WHERE "tenant_id" IN ($1, $2)`,
      TENANT_A,
      TENANT_B,
    );
    expect(row?.n).toBe(0);
  });
});
