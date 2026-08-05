# unierp-data

**Layer 2** of the UniERP layered repository architecture
(`PLATFORM_ARCHITECTURE.md` § 4.2). Publishes `@unerp/database`.

Depends on: L0 (`@unerp/contracts`).

## What lives here

The Prisma multi-file schema, migrations, RLS policies, seeds, and the
tenant-isolation test generator.

## Why it is its own repository

> "The data model versions independently of the code that uses it."
> — § 4.2

`@unerp/database` can ship a migration *ahead* of the API that uses it, which is
exactly what expand → migrate → contract requires (§ 4.3). A migration must stay
backward-compatible for one full train (§ 9), because that property is what lets
a rollback be one manifest rather than a database restore.

## The guarantee this repository owns

Layer 4 of the four-layer tenant isolation model — **the only layer that is
proof rather than convention** (§ 5.1):

- every tenant table carries `tenant_id`
- RLS `ENABLE` **and** `FORCE`, so the table owner is not exempt
- the application role is `NOBYPASSRLS`
- a two-tenant isolation test is *generated* per table, not hand-written

**Isolation tests must connect as the application role.** The migration/seed
role is a superuser, and a superuser bypasses RLS outright — a two-tenant test
run as the owner passes against a table with no policy at all, which makes it
worse than no test.

## Extraction status

Extracted from the `ERPSys` monorepo as § 14 Phase 3.3, **with full history**
(61 commits, 178 migrations) via `git-filter-repo`. History mattered here in a
way it did not for the shallower packages: these commits are the audit trail of
every schema change the platform has made.

The monorepo copy remains authoritative until a registry exists and consumers
are switched deliberately.
