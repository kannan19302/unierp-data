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
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { PrismaClient } from "@prisma/client";
import { PrismaClient as IdpPrismaClient } from "../src/idp-client/index.js";
import { PERMISSION_REGISTRY } from "@kannan19302/shared";
import { ensureProviderRealm } from "./provider-realm.js";

// Two clients, same split as seed.ts: Tenant lives in the core schema, while
// User/Role/UserRole live in idp-schema.prisma. Raw clients rather than the
// tenant-context wrappers exported from src/index.ts — this seed is creating
// the tenant it would otherwise need to already be scoped to.
const prisma = new PrismaClient();
const idpPrisma = new IdpPrismaClient();

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
 * realm === "provider" AND at least one PERMISSION in the `system.`,
 * `platform.`, or `pcc.` namespace — deliberately, so that a mis-seeded ROLE grant against
 * "*" can never open P2 to every tenant. A provider user whose role carries an
 * empty permissions array authenticates fine and is then refused the platform
 * with `access_denied`, which looks identical to a missing grant.
 *
 * Concrete permissions only. The dev-bypass route in provider-admin-os
 * (app/api/v1/auth/provider/login/route.ts) mints "*", "system.*", "platform.*"
 * and "admin.*"; those wildcards are exactly what control-plane.guard.ts and
 * the jwt-auth guard tests exist to distrust, so they are not seeded here.
 */
export const PROVIDER_STAFF_PERMISSIONS = [
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
  // Canonical application-entry permissions are concrete rather than a pcc.*
  // wildcard so a newly introduced PCC application is not silently granted
  // before its access policy is reviewed.
  ...PERMISSION_REGISTRY.filter(
    (permission) =>
      permission.code.startsWith("pcc.") && permission.action === "access",
  ).map((permission) => permission.code),
];

const STAFF_EMAIL = (
  process.env.BOOTSTRAP_PLATFORM_ADMIN_EMAIL ??
  process.env.PROVIDER_SEED_EMAIL ??
  "kannan19302@gmail.com"
).trim().toLowerCase();

async function main(): Promise<void> {
  const tenant = await ensureProviderRealm(prisma);

  // Provider principals live only in the reserved provider realm. Reusing a
  // customer identity row would let customer account lifecycle and provider
  // authority share one principal, defeating the realm boundary.
  let user = await idpPrisma.user.findFirst({
    where: {
      email: { equals: STAFF_EMAIL, mode: "insensitive" },
      tenantId: tenant.id,
      status: "ACTIVE",
      deletedAt: null,
    },
    orderBy: { createdAt: "asc" },
  });

  if (!user && !process.env.BOOTSTRAP_PLATFORM_ADMIN_PASSWORD_HASH?.trim()) {
    throw new Error(
      `Cannot bootstrap ${STAFF_EMAIL} without an approved existing principal or BOOTSTRAP_PLATFORM_ADMIN_PASSWORD_HASH`,
    );
  }

  if (!user) {
    user = await idpPrisma.user.create({
      data: {
        id: `usr-${randomUUID()}`,
        tenantId: tenant.id,
        email: STAFF_EMAIL,
        passwordHash:
          process.env.BOOTSTRAP_PLATFORM_ADMIN_PASSWORD_HASH!.trim(),
        firstName: "Platform",
        lastName: "Administrator",
        status: "ACTIVE",
      },
    });
  }

  const roleId = `role-${tenant.id}-${STAFF_ROLE}`;
  const role = await idpPrisma.role.upsert({
    where: { id: roleId },
    // Permissions are re-applied on update: this row decides whether a
    // provider-realm session can reach the control plane.
    update: { permissions: PROVIDER_STAFF_PERMISSIONS },
    create: {
      id: roleId,
      tenantId: tenant.id,
      name: STAFF_ROLE,
      isSystem: true,
      permissions: PROVIDER_STAFF_PERMISSIONS,
    },
    select: { id: true },
  });

  await idpPrisma.userRole.upsert({
    where: { userId_roleId: { userId: user.id, roleId: role.id } },
    update: {},
    create: { userId: user.id, roleId: role.id },
  });

  console.log(
    `provider realm ready — catalog tenant ${tenant.id}, principal ${user.id}, ${STAFF_EMAIL} (${STAFF_ROLE})`,
  );
}

const isEntryPoint =
  process.argv[1] !== undefined &&
  fileURLToPath(import.meta.url) === resolve(process.argv[1]);

if (isEntryPoint) {
  main()
    .catch((err) => {
      console.error(err);
      process.exitCode = 1;
    })
    .finally(async () => {
      await idpPrisma.$disconnect();
      await prisma.$disconnect();
    });
}
