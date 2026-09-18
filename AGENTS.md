<!-- UniERP-Agent-Protocol: 1.1.0 -->
# UniERP Repository Agent Entrypoint: Data & Persistence (`data`)

This repository is one delivery unit in the UniERP polyrepo. Before analysis, planning, review, or mutation, every
AI agent from every provider MUST read and follow:

1. the workspace entrypoint at [`../AGENTS.md`](../AGENTS.md);
2. the canonical standard at
   [`../platform/docs/standards/AI_AGENT_DEVELOPMENT_PROTOCOL.md`](../platform/docs/standards/AI_AGENT_DEVELOPMENT_PROTOCOL.md);
3. the owning platform documents selected through
   [`../platform/docs/PLATFORM_CATALOG.md`](../platform/docs/PLATFORM_CATALOG.md).

If the workspace entrypoint or canonical standard is unavailable, the protocol bundle is incomplete. The agent
MUST stop before mutation and report the missing dependency. This bootstrap adds no weaker or conflicting rules.
Repository-specific additions may be appended below only when they narrow implementation behavior without
redefining platform ownership, security, contracts, or cross-platform standards.

---

## 1. Repository Identity & Mission

- **Repository**: `data`
- **Platform Owner**: `PLT-BIZ` (Data & Persistence Architecture)
- **Architectural Layer**: **Layer 2 (Data & Persistence)**
- **Database Engine**: PostgreSQL 16 with `pgvector`
- **Mission**: Authoritative home of the UniERP database schema, Prisma models, immutable SQL migrations, transactional outbox tables, audit log partitions, and PostgreSQL Row-Level Security (RLS) policies.

---

## 2. Inviolable Database Invariants & Security Guidance

1. **PostgreSQL Row-Level Security (RLS) Universality**:
   - EVERY tenant-owned table MUST enforce RLS with `FORCE ROW LEVEL SECURITY`.
   - Security policies MUST evaluate `app.current_tenant_id` session setting.
   - Applications and integration tests MUST connect with a `NOBYPASSRLS` database role.
   - Every tenant table requires positive (same-tenant access), negative (cross-tenant denied), and no-context (denied) test evidence.
2. **Migration Safety & Immutability**:
   - Database changes use expand/backfill/contract migrations.
   - Destructive operations (`DROP TABLE`, `DROP COLUMN`, `TRUNCATE`, unqualified `DELETE`) are strictly forbidden in automated deployments.
   - Index creation MUST use `CREATE INDEX CONCURRENTLY`.
   - Never reset, force-push, or mutate committed historical migrations.
3. **Financial & Numerical Correctness**:
   - Currency and financial amounts: `Decimal(19,4)` strictly.
   - Inventory stock and counts: `Decimal(19,4)` strictly. Zero floating-point types (`Float`) on financial columns.
4. **Transactional Outbox**:
   - Business state mutations and domain events MUST commit atomically in the same database transaction via the `outbox_events` table.

---

## 3. Industrial Software Engineering Standards

1. **Zero Scratch Dumps**:
   - Ad-hoc `.sql` dumps, diff scripts, or temporary test logs must never be committed in the repository root.
2. **Schema Organization**:
   - Modular Prisma schema files in `prisma/schema/` grouped logically by domain (`core`, `finance`, `inventory`, `hr`, `sales`, etc.).

---

## 4. Verification Gates & Mandatory Toolchain

Before declaring any cycle `DONE`, run and verify:

```powershell
pnpm prisma generate         # Regenerate Prisma Client
pnpm typecheck               # Strict TypeScript verification
pnpm test                    # RLS and migration safety tests
node scripts/check-layer.mjs  # Canonical Layer Gate enforcement
```
