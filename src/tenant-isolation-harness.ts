// ─────────────────────────────────────────────────
// Two-tenant isolation harness — reusable proof that
// "tenant B gets zero rows" for any protected table.
//
// Phase J03. One line per entity:
//
//   await assertTenantIsolation({ table, app, owner });
//
// The harness does the rest: it checks the RLS policy
// structurally, seeds a minimal row for tenant A and
// tenant B, then proves over a NOBYPASSRLS connection
// that A sees its own row and zero of B's rows.
//
// The seeder introspects the table and builds a
// constraint-satisfying minimal row, using
// `session_replication_role = replica` (superuser only)
// inside a transaction so FK/check triggers and
// application triggers are skipped and the setting
// reverts on COMMIT. This is what makes one generic
// seeder able to cover every protected table, from a
// plain `customers` row to a 1536-dimension vector.
//
// This module is DB-derived on purpose: the catalogue
// comes from the running database (every public table
// carrying a tenant column), so a new tenant table is
// covered the moment its migration lands, and cannot
// be missed by a stale hardcoded list.
// ─────────────────────────────────────────────────

import { PrismaClient } from "./main-client/index.js";
import { randomUUID } from "node:crypto";

export const TENANT_A = "j03-iso-tenant-a";
export const TENANT_B = "j03-iso-tenant-b";

/** All accepted spellings of a tenant column, matching check-rls-verify.mjs. */
export const TENANT_COLUMN_NAMES = ["tenant_id", "tenantId"] as const;

/** Type-guard for the tenant-column spellings. */
export function isTenantColumnName(value: string): value is (typeof TENANT_COLUMN_NAMES)[number] {
  return value === "tenant_id" || value === "tenantId";
}

export type ProtectedTable = {
  /** The physical table name. */
  table: string;
  /** The tenant column actually present on this table. */
  tenantColumn: string;
  /** True when RLS is ENABLED, FORCED and carries a tenant_isolation_<table> policy. */
  protected: boolean;
};

type ColumnMeta = {
  column_name: string;
  data_type: string;
  udt_name: string;
  is_nullable: string;
  column_default: string | null;
  is_generated: string;
  is_identity: string;
  character_maximum_length: number | null;
};

type RawClient = Pick<PrismaClient, "$queryRawUnsafe" | "$executeRawUnsafe">;

let colCache = new Map<string, ColumnMeta[]>();
let uniqueCache = new Map<string, Set<string>>();
let enumCache = new Map<string, string | null>();

/** Exported for tests that want to reset introspection caches between runs. */
export function _resetHarnessCaches() {
  colCache = new Map();
  uniqueCache = new Map();
  enumCache = new Map();
}

/** The catalogue — every public base table carrying a tenant column, DB-derived. */
export async function listProtectedTables(
  owner: PrismaClient,
): Promise<ProtectedTable[]> {
  const rows = await owner.$queryRawUnsafe<Array<{ table_name: string }>>(
    `SELECT c.relname::text AS table_name
       FROM pg_class c
       JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relkind = 'r'
        AND c.relname != '_prisma_migrations'
        AND EXISTS (
          SELECT 1 FROM information_schema.columns ic
           WHERE ic.table_schema = 'public'
             AND ic.table_name = c.relname
             AND ic.column_name IN ('tenant_id', 'tenantId')
        )
      ORDER BY c.relname`,
  );
  const out: ProtectedTable[] = [];
  for (const { table_name } of rows) {
    const cols = await columnMeta(owner, table_name);
    const tenantColumn = cols.find((c) =>
      isTenantColumnName(c.column_name),
    )?.column_name as string;
    out.push({
      table: table_name,
      tenantColumn,
      protected: await tableProtection(owner, table_name),
    });
  }
  return out;
}

/** Structural RLS state for one table (ENABLE + FORCE + policy present). */
async function tableProtection(
  owner: PrismaClient,
  table: string,
): Promise<boolean> {
  const rows = await owner.$queryRawUnsafe<
    Array<{ rls: boolean; forced: boolean; has_policy: boolean }>
  >(
    `SELECT c.relrowsecurity AS rls,
            c.relforcerowsecurity AS forced,
            EXISTS (
              SELECT 1 FROM pg_policies p
               WHERE p.schemaname = 'public' AND p.tablename = c.relname
                 AND p.policyname = 'tenant_isolation_' || c.relname
            ) AS has_policy
       FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = $1 AND c.relkind = 'r'`,
    table,
  );
  if (!rows[0]) return false;
  return rows[0].rls && rows[0].forced && rows[0].has_policy;
}

async function columnMeta(
  client: RawClient,
  table: string,
): Promise<ColumnMeta[]> {
  if (colCache.has(table)) return colCache.get(table)!;
  const cols = await client.$queryRawUnsafe<ColumnMeta[]>(
    `SELECT c.column_name, c.data_type, c.udt_name, c.is_nullable, c.column_default,
            c.is_generated, c.is_identity, c.character_maximum_length
       FROM information_schema.columns c
      WHERE c.table_schema = 'public' AND c.table_name = $1
      ORDER BY c.ordinal_position`,
    table,
  );
  colCache.set(table, cols);
  return cols;
}

/** Every column participating in a unique index (constraint OR raw index). */
async function uniqueColumns(
  client: RawClient,
  table: string,
): Promise<Set<string>> {
  if (uniqueCache.has(table)) return uniqueCache.get(table)!;
  const rows = await client.$queryRawUnsafe<Array<{ column_name: string }>>(
    `SELECT a.attname::text AS column_name
       FROM pg_index x
       JOIN pg_class t ON t.oid = x.indrelid
       JOIN pg_namespace n ON n.oid = t.relnamespace
       JOIN unnest(x.indkey) WITH ORDINALITY AS k(attnum, ord) ON true
       JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
      WHERE n.nspname = 'public' AND t.relname = $1 AND x.indisunique AND a.attnum > 0`,
    table,
  );
  const set = new Set(rows.map((r) => r.column_name));
  uniqueCache.set(table, set);
  return set;
}

async function enumFirstValue(
  client: RawClient,
  udtName: string,
): Promise<string | null> {
  if (enumCache.has(udtName)) return enumCache.get(udtName)!;
  try {
    const rows = await client.$queryRawUnsafe<Array<{ enumlabel: string }>>(
      `SELECT e.enumlabel
         FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
        WHERE t.typname = $1
        ORDER BY e.enumsortorder LIMIT 1`,
      udtName,
    );
    enumCache.set(udtName, rows[0]?.enumlabel ?? null);
  } catch {
    enumCache.set(udtName, null);
  }
  return enumCache.get(udtName)!;
}

async function vectorDims(
  client: RawClient,
  table: string,
  column: string,
): Promise<number> {
  try {
    const rows = await client.$queryRawUnsafe<Array<{ ftype: string }>>(
      `SELECT format_type(a.atttypid, a.atttypmod) AS ftype
         FROM pg_attribute a
         JOIN pg_class c ON c.oid = a.attrelid
         JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = $1 AND a.attname = $2`,
      table,
      column,
    );
    const m = rows[0]?.ftype?.match(/vector\((\d+)\)/);
    return m?.[1] ? parseInt(m[1], 10) : 3;
  } catch {
    return 3;
  }
}

/**
 * Insert one minimal constraint-satisfying row for the given tenant.
 * Runs inside a transaction with `session_replication_role = replica`,
 * which skips FK/check triggers and application triggers, then reverts.
 */
export async function seedMinimalRow(
  owner: PrismaClient,
  table: string,
  tenantColumn: string,
  tenantId: string,
): Promise<void> {
  await owner.$transaction(async (tx) => {
    await tx.$executeRawUnsafe(`SET LOCAL session_replication_role = replica`);
    const cols = await columnMeta(tx as unknown as RawClient, table);
    const uniq = await uniqueColumns(tx as unknown as RawClient, table);
    const suffix = randomUUID().replace(/-/g, "").slice(0, 16);
    const insertCols: string[] = [];
    const valExprs: string[] = [];
    const values: unknown[] = [];

    const push = (name: string, expr: string, val?: unknown) => {
      insertCols.push(`"${name}"`);
      if (expr) {
        if (val !== undefined) {
          const p = `$${values.length + 1}`;
          valExprs.push(expr.replace("$?", p));
          values.push(val);
        } else {
          valExprs.push(expr);
        }
      } else {
        valExprs.push(`$${values.length + 1}`);
        values.push(val);
      }
    };

    for (const c of cols) {
      if (c.column_name === tenantColumn) {
        insertCols.push(`"${tenantColumn}"`);
        valExprs.push(`$${values.length + 1}`);
        values.push(tenantId);
        continue;
      }
      if (c.is_generated === "ALWAYS") continue;
      if (c.is_identity === "YES") continue;
      const isUnique = uniq.has(c.column_name);
      // Skip columns with a DB default (they will fill themselves) unless the
      // column is in a unique index — a default value would collide between
      // the two seeded rows, and a unique column must get a fresh value.
      if (!isUnique && c.column_default) continue;
      // Nullable non-unique columns can stay NULL.
      if (!isUnique && c.is_nullable === "YES") continue;

      const udt = c.udt_name as string;
      const name = c.column_name as string;
      const unique = isUnique;
      switch (udt) {
        case "uuid":
          push(name, "", randomUUID());
          break;
        case "text":
        case "varchar":
        case "bpchar":
        case "citext": {
          const maxLen = (c.character_maximum_length as number) ?? 255;
          const v = `j03-${suffix}-${name}`.slice(0, Math.max(maxLen, 12));
          push(name, "", v);
          break;
        }
        case "int2":
        case "int4":
        case "int8":
          push(name, unique ? `${Math.floor(Math.random() * 1e9)}` : "0");
          break;
        case "numeric":
        case "float4":
        case "float8":
          push(name, unique ? `${Math.floor(Math.random() * 1e6)}.00` : "0");
          break;
        case "bool":
          push(name, "false");
          break;
        case "timestamptz":
        case "timestamp":
        case "date":
          push(name, "now()");
          break;
        case "json":
        case "jsonb":
          push(name, "'{}'::jsonb");
          break;
        case "bytea":
          push(name, `'\\x00'::bytea`);
          break;
        case "vector": {
          const d = await vectorDims(tx as unknown as RawClient, table, name);
          push(
            name,
            `array_to_vector(ARRAY(SELECT 0::float8 FROM generate_series(1,${d})),${d},false)`,
          );
          break;
        }
        default:
          if (c.data_type === "ARRAY") {
            push(name, `'{}'::${udt}`);
          } else {
            const ev = await enumFirstValue(tx as unknown as RawClient, udt);
            if (ev) push(name, `$?::"${udt}"`, ev);
            else
              throw new Error(
                `seeder: no generator for "${table}"."${name}" (udt ${udt})`,
              );
          }
      }
    }
    const sql = `INSERT INTO "${table}" (${insertCols.join(",")}) VALUES (${valExprs.join(",")})`;
    await tx.$executeRawUnsafe(sql, ...values);
  });
}

/** The one-line-per-entity assertion — see the module header for usage. */
export async function assertTenantIsolation(
  opts: {
    owner: PrismaClient;
    app: PrismaClient;
    table: string;
    tenantColumn?: string;
    tenantA?: string;
    tenantB?: string;
  },
): Promise<void> {
  const { owner, app, table } = opts;
  const tenantA = opts.tenantA ?? TENANT_A;
  const tenantB = opts.tenantB ?? TENANT_B;

  const cols = await columnMeta(owner, table);
  const tenantColumn =
    opts.tenantColumn ??
    (cols.find((c) => isTenantColumnName(c.column_name))
      ?.column_name as string);
  if (!tenantColumn) {
    throw new Error(`${table}: no tenant column found`);
  }
  if (!(await tableProtection(owner, table))) {
    throw new Error(
      `${table}: no RLS enforcement — rls/forced/policy (tenant_isolation_${table}) must all hold`,
    );
  }

  // Verify the app connection really is a NOBYPASSRLS role — a proof over a
  // superuser or BYPASSRLS role is a proof of nothing.
  const [role] = await app.$queryRawUnsafe<
    Array<{ rolsuper: boolean; rolbypassrls: boolean }>
  >(`SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user`);
  if (role?.rolsuper || role?.rolbypassrls) {
    throw new Error(`${table}: isolation proof must run as a NOBYPASSRLS role`);
  }

  // Clean any rows left by a previous aborted run, then seed both tenants.
  await seedMinimalRow(owner, table, tenantColumn, tenantA);
  await seedMinimalRow(owner, table, tenantColumn, tenantB);

  try {
    const countFor = async (tenant: string): Promise<number> => {
      const [row] = await app.$transaction(async (tx) => {
        await tx.$executeRawUnsafe(
          `SELECT set_config('app.current_tenant_id', $1, true)`,
          tenantA,
        );
        return tx.$queryRawUnsafe<Array<{ n: string | number }>>(
          `SELECT count(*)::int AS n FROM "${table}" WHERE "${tenantColumn}" = $1`,
          tenant,
        );
      });
      return Number(row?.n ?? 0);
    };

    const bRowsVisibleToA = await countFor(tenantB);
    if (bRowsVisibleToA !== 0) {
      throw new Error(
        `${table}: tenant A can see ${bRowsVisibleToA} row(s) belonging to tenant B`,
      );
    }

    const aRowsVisibleToA = await countFor(tenantA);
    if (aRowsVisibleToA < 1) {
      throw new Error(
        `${table}: positive control failed — tenant A cannot see its own seeded row (policy too strict?)`,
      );
    }
  } finally {
    // Owner bypasses RLS, so cleanup is unconditional.
    await owner.$transaction(async (tx) => {
      await tx.$executeRawUnsafe(`SET LOCAL session_replication_role = replica`);
      await tx.$executeRawUnsafe(
        `DELETE FROM "${table}" WHERE "${tenantColumn}" IN ($1, $2)`,
        tenantA,
        tenantB,
      );
    });
  }
}
