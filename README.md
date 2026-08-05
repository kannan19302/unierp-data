# unierp-data

**Layer L2 — Runtime** of the [UniERP](../unierp-platform) platform.
Depends on: L0.

## What this is

The Prisma multi-file schema, migrations, RLS policies, seeds, and the tenant-isolation test generator.

## The invariant this repository owns

**This repository owns the only layer of tenant isolation that is proof rather than convention:** RLS `ENABLE` and `FORCE` on every tenant table, an application role that is `NOBYPASSRLS`, and a generated two-tenant test per table. Isolation tests must connect as the *application* role — a test run as the owner passes against a table with no policy at all.

## The rule that applies everywhere

A repository may depend only on published artifacts of a **strictly lower
layer** — never sideways within a layer, never upward. A cycle is not
discouraged; it is unrepresentable, because the lower layer's package cannot
name the higher one.

See the [platform overview](../unierp-platform/README.md) for the full map, and
[`PLATFORM_ARCHITECTURE.md`](../ERPSys/docs/PLATFORM_ARCHITECTURE.md) § 4.2 for
the reasoning.

## Licence

AGPL-3.0.
