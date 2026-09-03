#!/usr/bin/env node
/**
 * RLS verification — schema-derived, per-table, zero exemptions.
 *
 * Phase A05. Replaces the count-based `check-rls-verify.mjs` that could not fail:
 * it summed tables with `tenant_id` columns and RLS policies and printed PASS when
 * both counts were positive. Sixteen tenant tables carried the tenant column as
 * `tenantId` (camelCase) rather than `tenant_id`, so every `tenant_id`-matched
 * loop and check — this script's predecessor, the F5 catch-up, the integration
 * suite, the migration-safety scan — was blind to them, and they shipped with RLS
 * DISABLED and no policy at all. A check that cannot see a gap reports clean
 * while the tenant boundary is open: that is ARCHITECTURE_REVIEW § F5 again.
 *
 * This check derives the EXPECTED tenant table set from the Prisma schema on
 * every run — not from a catalogue captured once — so it cannot go stale: a new
 * model with a tenantId field becomes a required, individually-verified table the
 * moment it is added to the schema. There is no exemption list and no allowlist:
 * every schema-declared tenant table must exist, have RLS ENABLED and FORCED, and
 * carry a policy named `tenant_isolation_<table>` referencing its tenant column.
 * The 364 tables named in ARCHITECTURE_REVIEW § F5 are individually confirmed.
 *
 *   DATABASE_APP_URL=... node scripts/check-rls-verify.mjs
 *
 * Exit 0: every expected table verified. Exit 1: any single table failed, listed.
 */
import { readdirSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { PrismaClient } from "@prisma/client";
import { F5 } from "./f5-rls-tables.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");
const SCHEMA_DIR = join(ROOT, "prisma", "schema");
const IDP_SCHEMA = join(ROOT, "prisma", "idp-schema.prisma");

/** Parse one Prisma schema file into models-with-a-tenant-field. */
function parseSchemaFile(file, expected) {
  const lines = readFileSync(file, "utf8").split("\n");
  let model = null;
  let tenantField = null;
  let tableName = null;
  const source = file.split(/[\\/]/).pop();
  for (const raw of lines) {
    const line = raw.trim();
    if (!line || line.startsWith("//")) continue;
    const m = line.match(/^model\s+(\w+)\s*\{/);
    if (m) {
      model = m[1];
      tenantField = null;
      tableName = null;
      continue;
    }
    if (line === "}") {
      if (model && tenantField) {
        const table = tableName ?? toSnake(model);
        expected.set(table, { model, column: tenantField.column, source });
      }
      model = null;
      continue;
    }
    if (!model) continue;
    if (/^tenantId\s+/.test(line) && !/^tenantIds\s+/.test(line)) {
      const map = line.match(/@map\(\s*"([^"]+)"\s*\)/);
      tenantField = { column: map ? map[1] : "tenantId" };
    } else if (/^tenant_id\s+/.test(line)) {
      tenantField = { column: "tenant_id" };
    } else if (/^@@map\(\s*"([^"]+)"\s*\)/.test(line)) {
      tableName = line.match(/^@@map\(\s*"([^"]+)"\s*\)/)[1];
    }
  }
  return expected;
}

function toSnake(s) {
  return s.replace(/[A-Z]/g, (c) => "_" + c.toLowerCase()).replace(/^_/, "");
}

/** The expected tenant tables, re-derived from the schema every run. */
function expectedTenantTables() {
  const expected = new Map();
  for (const f of readdirSync(SCHEMA_DIR).filter((f) => f.endsWith(".prisma"))) {
    parseSchemaFile(join(SCHEMA_DIR, f), expected);
  }
  parseSchemaFile(IDP_SCHEMA, expected);
  return expected;
}

if (!process.env.DATABASE_APP_URL) {
  throw new Error(
    "DATABASE_APP_URL is required. RLS verification must use the NOBYPASSRLS application role, not a migration-owner connection.",
  );
}

const prisma = new PrismaClient({
  datasources: { db: { url: process.env.DATABASE_APP_URL } },
});
const failures = [];
const confirmed = [];

async function main() {
  const expected = expectedTenantTables();

  let currentRole;
  try {
    [currentRole] = await prisma.$queryRawUnsafe(
      `SELECT current_user::text AS name, rolsuper, rolbypassrls
         FROM pg_roles WHERE rolname = current_user`,
    );
  } catch (err) {
    if (!process.env.DOCKER_DELEGATED) {
      try {
        const { spawnSync } = await import("node:child_process");
        const containerUrl = process.env.DATABASE_APP_URL.includes("localhost") || process.env.DATABASE_APP_URL.includes("127.0.0.1")
          ? process.env.DATABASE_APP_URL.replace(/localhost|127\.0\.0\.1/, "postgres")
          : process.env.DATABASE_APP_URL;
        spawnSync("docker", ["exec", "api", "mkdir", "-p", "/tmp/rls-check/scripts"], { stdio: "ignore" });
        spawnSync("docker", ["cp", `${join(HERE, "check-rls-verify.mjs")}`, "api:/tmp/rls-check/scripts/check-rls-verify.mjs"], { stdio: "ignore" });
        spawnSync("docker", ["cp", `${join(HERE, "f5-rls-tables.mjs")}`, "api:/tmp/rls-check/scripts/f5-rls-tables.mjs"], { stdio: "ignore" });
        spawnSync("docker", ["cp", `${join(ROOT, "prisma")}`, "api:/tmp/rls-check/prisma"], { stdio: "ignore" });
        spawnSync("docker", ["exec", "api", "ln", "-sfn", "/app/node_modules", "/tmp/rls-check/node_modules"], { stdio: "ignore" });
        const r = spawnSync(
          "docker",
          ["exec", "-e", `DATABASE_APP_URL=${containerUrl}`, "-e", "DOCKER_DELEGATED=1", "api", "node", "/tmp/rls-check/scripts/check-rls-verify.mjs"],
          { stdio: "inherit" },
        );
        if (r.status === 0) process.exit(0);
        process.exit(r.status ?? 1);
      } catch {
        throw err;
      }
    }
    throw err;
  }

  if (!currentRole) {
    failures.push("could not determine the role used for RLS verification");
  } else if (currentRole.rolsuper || currentRole.rolbypassrls) {
    failures.push(
      `RLS verifier is connected as privileged role ${currentRole.name}; verification requires NOSUPERUSER NOBYPASSRLS application credentials`,
    );
  }

  const rows = await prisma.$queryRawUnsafe(
    `SELECT c.relname::text as table_name,
            c.relrowsecurity as rls,
            c.relforcerowsecurity as forced,
            (SELECT string_agg(pol.policyname, ',' ORDER BY pol.policyname)
               FROM pg_policies pol
              WHERE pol.schemaname = 'public' AND pol.tablename = c.relname) as policies,
            (SELECT string_agg(pol.qual, ' | ')
               FROM pg_policies pol
              WHERE pol.schemaname = 'public' AND pol.tablename = c.relname
                AND pol.policyname = 'tenant_isolation_' || c.relname) as policy_qual,
            (SELECT string_agg(pol.with_check, ' | ')
               FROM pg_policies pol
              WHERE pol.schemaname = 'public' AND pol.tablename = c.relname
                AND pol.policyname = 'tenant_isolation_' || c.relname) as policy_check
     FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname != '_prisma_migrations'`,
  );
  const db = new Map(rows.map((r) => [r.table_name, r]));

  // ── 1. every schema-declared tenant table must exist and be protected ────────
  for (const [table, e] of [...expected].sort((a, b) => a[0].localeCompare(b[0]))) {
    const d = db.get(table);
    if (!d) {
      failures.push(`schema declares tenant table "${table}" (${e.model}, ${e.source}) but no such table exists in the DB`);
      continue;
    }
    const hasPolicy = d.policies?.split(",").includes(`tenant_isolation_${table}`) ?? false;
    const policyRefsColumn =
      hasPolicy &&
      d.policy_qual?.includes(e.column) &&
      d.policy_qual?.includes("current_tenant_id()");
    if (!d.rls || !d.forced || !hasPolicy || !policyRefsColumn) {
      failures.push(
        `${table}: rls=${!!d.rls} forced=${!!d.forced} policy=tenant_isolation_${table} (${hasPolicy ? "present" : "MISSING"})` +
          (hasPolicy && !policyRefsColumn ? " policy does not reference tenant column" : ""),
      );
    }
  }

  // ── 2. every DB table carrying a tenant column must be protected ─────────────
  // Catches tables created outside the schema (e.g. runtime DDL co_* and ext_* tables,
  // closing D143), or schemas renamed away from a table, that would otherwise be
  // invisible to the schema-derived pass above.
  const runtimeDdlTables = [];
  for (const [table, d] of [...db].sort((a, b) => a[0].localeCompare(b[0]))) {
    const isRuntimePrefix = table.startsWith("co_") || table.startsWith("ext_");
    const cols = await prisma.$queryRawUnsafe(
      `SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name=$1`,
      table,
    );
    const tenantCol = cols.find((c) => c.column_name === "tenant_id" || c.column_name === "tenantId");
    
    if (isRuntimePrefix) {
      runtimeDdlTables.push(table);
      if (!tenantCol) {
        failures.push(`Runtime DDL table "${table}" (D143) is missing required tenant_id column.`);
      }
    }

    if (!tenantCol) continue;
    const hasPolicy = d.policies?.split(",").includes(`tenant_isolation_${table}`) ?? false;
    if (!d.rls || !d.forced || !hasPolicy) {
      failures.push(
        `DB table "${table}" has tenant column "${tenantCol.column_name}" but rls=${!!d.rls} forced=${!!d.forced} policy=${hasPolicy ? "present" : "MISSING"}${isRuntimePrefix ? " (runtime DDL table, D143)" : ""}`,
      );
    }
  }

  // ── 3. the 364 ARCHITECTURE_REVIEW § F5 tables, individually confirmed ────────
  for (const table of F5) {
    const d = db.get(table);
    const ok =
      d && d.rls && d.forced && d.policies?.split(",").includes(`tenant_isolation_${table}`);
    if (!ok) {
      failures.push(`F5 table "${table}" is NOT covered`);
    } else {
      confirmed.push(table);
    }
  }

  // ── 4. the app role must not bypass RLS ──────────────────────────────────────
  const [role] = await prisma.$queryRawUnsafe(
    `SELECT rolname, rolbypassrls::int as bypass FROM pg_roles WHERE rolname = 'unerp_api'`,
  );
  if (!role) {
    failures.push("role unerp_api does not exist — the application connects as something else");
  } else if (role.bypass !== 0) {
    failures.push("role unerp_api has BYPASSRLS — every policy above is decorative");
  }

  const f5Missing = F5.filter((t) => !confirmed.includes(t)).length;

  console.log(`\nRLS verification — schema-derived, per-table`);
  console.log(`  expected tenant tables (from schema): ${expected.size}`);
  console.log(`  runtime DDL tables checked (D143):    ${runtimeDdlTables.length}`);
  console.log(`  F5 tables confirmed individually:     ${confirmed.length}/${F5.length}${f5Missing ? ` (${f5Missing} NOT covered)` : ""}`);
  console.log(`  failures:                             ${failures.length}`);

  await prisma.$disconnect();
  if (failures.length) {
    console.error(`\n  ${failures.length} blocking issue(s):\n`);
    for (const f of failures) console.error(`  ❌ ${f}`);
    console.error(
      `\n  No exemptions. A schema-declared tenant table with RLS off, FORCE off, or a\n` +
        `  missing/mis-referenced tenant_isolation_<table> policy is a cross-tenant data\n` +
        `  leak, and a DB table carrying a tenant column without RLS is the same.\n`,
    );
    process.exit(1);
  }
  console.log(`\n  ✅ Zero exemptions — every tenant table carries RLS + FORCE + a tenant_isolation policy.\n`);
  process.exit(0);
}

main().catch(async (e) => {
  console.error(e);
  await prisma.$disconnect().catch(() => {});
  process.exit(1);
});
