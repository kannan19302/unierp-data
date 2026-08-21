/**
 * Seeds the PROVIDER realm — the UniERP-internal tenant that Provider Admin OS
 * (P2, port 4002) authenticates against.
 *
 * Why this file has to exist: the hosted login page routes by platform
 * audience. `idp/src/modules/oidc/controllers/login.controller.ts` checks
 * whether the platform behind `return_to` is INTERNAL and, if so, calls
 * `AuthService.providerLogin` instead of the ordinary tenant `login`. That
 * method opens with:
 *
 *     const tenant = await prisma.tenant.findUnique({ where: { slug: "provider" } });
 *     if (!tenant) throw new UnauthorizedException("Provider realm not configured");
 *
 * and nothing in the repository ever created a tenant with that slug. So every
 * sign-in to Provider Admin OS failed for every account — and because the
 * controller deliberately collapses all failures into one message so the form
 * is not an account-enumeration oracle, it surfaced as "Invalid email or
 * password" with correct credentials. The console was unreachable, and the
 * error said the opposite of the cause.
 *
 * The realm separation itself is the design, not the bug: provider staff are
 * NOT tenant users, and phases 7 and 8 of idp/scripts/verify-oidc-flow.mjs
 * exist to prove a tenant account cannot reach the control plane even holding a
 * wildcard. This seed populates the provider side of that boundary; it does not
 * move it.
 *
 * Idempotent: safe to re-run, and re-running is how changes reach an existing
 * environment.
 *
 *   pnpm tsx prisma/seed-provider-realm.ts
 */
import { randomUUID } from "node:crypto";
import { PrismaClient } from "@prisma/client";
import { PrismaClient as IdpPrismaClient } from "../src/idp-client/index.js";

// Two clients, same split as seed.ts: Tenant lives in the core schema, while
// User/Role/UserRole live in idp-schema.prisma. Raw clients rather than the
// tenant-context wrappers exported from src/index.ts — this seed is creating
// the tenant it would otherwise need to already be scoped to.
const prisma = new PrismaClient();
const idpPrisma = new IdpPrismaClient();

const TENANT_SLUG = "provider";
const TENANT_ID = "tnt-provider";

/**
 * Must match a role named in PROVIDER_STAFF_ROLES in seed-platform-entitlement.ts
 * — those are the roles `platform_grants` gives P2 to. A provider user with no
 * such role authenticates but is then refused the platform, which is correct and
 * also indistinguishable from a broken seed, so grant the strongest one here.
 */
const STAFF_ROLE = "platform.admin";

/**
 * The role NAME is not what admits this account to the control plane.
 * PlatformEntitlementService.holdsControlPlaneAuthority requires
 * realm === "provider" AND at least one PERMISSION in the `system.` or
 * `platform.` namespace — deliberately, so that a mis-seeded ROLE grant against
 * "*" can never open P2 to every tenant. A provider user whose role carries an
 * empty permissions array authenticates fine and is then refused the platform
 * with `access_denied`, which looks identical to a missing grant.
 *
 * Concrete permissions only. The dev-bypass route in provider-admin-os
 * (app/api/v1/auth/provider/login/route.ts) mints "*", "system.*", "platform.*"
 * and "admin.*"; those wildcards are exactly what control-plane.guard.ts and
 * the jwt-auth guard tests exist to distrust, so they are not seeded here.
 */
const STAFF_PERMISSIONS = [
  "system.tenant.read",
  "system.tenant.view",
  "system.tenant.update",
  "system.tenant.create",
  "system.tenant.provision",
  "system.tenant.security",
  "system.tenant.impersonate",
  "system.health.read",
  "system.analytics.read",
  "system.operations.read",
  "system.operations.backup",
  "system.superadmin.access",
  "system.security.admin",
];

const STAFF_EMAIL = process.env.PROVIDER_SEED_EMAIL ?? "staff@unierp.dev";

/**
 * Pre-hashed password for 'ProviderPassw0rd!' (bcrypt, cost 12) — same
 * convention as DEFAULT_PASSWORD_HASH in seed.ts, and for the same reason:
 * this package does not depend on bcryptjs and should not grow a dependency
 * just to seed one row.
 *
 * To regenerate:
 *   node -e "require('bcryptjs').hash('NEW',12).then(console.log)"
 */
const STAFF_PASSWORD_HASH =
  "$2a$12$k2xLuPQvhK.QOt7qJSQNQ.awYgCoBPCrGlPGMcxiNILnpm6qJ2mi.";

async function main(): Promise<void> {
  const tenant = await prisma.tenant.upsert({
    where: { slug: TENANT_SLUG },
    update: {},
    create: {
      id: TENANT_ID,
      name: "UniERP (Provider)",
      slug: TENANT_SLUG,
      plan: "internal",
      status: "ACTIVE",
    },
    select: { id: true },
  });

  const role = await idpPrisma.role.upsert({
    where: { id: `role-${TENANT_SLUG}-${STAFF_ROLE}` },
    // Permissions are re-applied on update: this is the row that decides whether
    // the control plane is reachable at all, so a re-run must repair it.
    update: { permissions: STAFF_PERMISSIONS },
    create: {
      id: `role-${TENANT_SLUG}-${STAFF_ROLE}`,
      tenantId: tenant.id,
      name: STAFF_ROLE,
      isSystem: true,
      permissions: STAFF_PERMISSIONS,
    },
    select: { id: true },
  });

  const user = await idpPrisma.user.upsert({
    where: { tenantId_email: { tenantId: tenant.id, email: STAFF_EMAIL } },
    update: { passwordHash: STAFF_PASSWORD_HASH, status: "ACTIVE" },
    create: {
      id: `usr-${randomUUID()}`,
      tenantId: tenant.id,
      email: STAFF_EMAIL,
      passwordHash: STAFF_PASSWORD_HASH,
      firstName: "Platform",
      lastName: "Staff",
      status: "ACTIVE",
    },
    select: { id: true },
  });

  await idpPrisma.userRole.upsert({
    where: { userId_roleId: { userId: user.id, roleId: role.id } },
    update: {},
    create: { userId: user.id, roleId: role.id },
  });

  console.log(`provider realm ready — tenant ${tenant.id}, ${STAFF_EMAIL} (${STAFF_ROLE})`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(async () => {
    await idpPrisma.$disconnect();
    await prisma.$disconnect();
  });
