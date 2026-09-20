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

process.env.DATABASE_URL = process.env.DATABASE_URL || "postgresql://unerp:unerp_password@localhost:5432/unerp_dev";
process.env.IDP_DATABASE_URL = process.env.IDP_DATABASE_URL || "postgresql://unerp:unerp_password@localhost:5432/unerp_dev";

// Two clients, same split as seed.ts: Tenant lives in the core schema, while
// User/Role/UserRole live in idp-schema.prisma. Raw clients rather than the
// tenant-context wrappers exported from src/index.ts — this seed is creating
// the tenant it would otherwise need to already be scoped to.
const prisma = new PrismaClient();
const idpPrisma = new IdpPrismaClient();

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
  "platform.admin",
  "platform.overview.read",
  // Canonical application-entry permissions are concrete rather than a pcc.*
  // wildcard so a newly introduced PCC application is not silently granted
  // before its access policy is reviewed.
  ...PERMISSION_REGISTRY.filter(
    (permission) =>
      permission.code.startsWith("pcc.") && permission.action === "access",
  ).map((permission) => permission.code),
];


const STAFF_ROLES = ["platform.admin", "SUPER_ADMIN"];

const STAFF_ACCOUNTS = [
  {
    email: (
      process.env.BOOTSTRAP_PLATFORM_ADMIN_EMAIL ??
      process.env.PROVIDER_SEED_EMAIL ??
      "kannan19302@gmail.com"
    ).trim().toLowerCase(),
    passwordHash:
      process.env.BOOTSTRAP_PLATFORM_ADMIN_PASSWORD_HASH?.trim() ||
      "$2a$10$QNgJRZXhmjzcu16TQaaR4.EfRNWCFvCxE0Jvqvy/IKIgwq.BgSMJG",
    firstName: "Platform",
    lastName: "Administrator",
  },
  {
    email: "provider.test.agent@unierp.com",
    passwordHash: "$2a$10$EKREbiE1.Z.uEdkapt2bMusYgL7LM2ghWb/xZGwmenCNV4Bgv/omC", // TestAgent123!
    firstName: "Universal Test",
    lastName: "Agent",
  },
];

async function main(): Promise<void> {
  const tenant = await ensureProviderRealm(prisma);

  // Ensure both platform.admin and SUPER_ADMIN roles exist in the provider realm
  const roleIds: string[] = [];
  for (const roleName of STAFF_ROLES) {
    const existingRole = await idpPrisma.role.findFirst({
      where: { tenantId: tenant.id, name: roleName },
    });
    if (existingRole) {
      await idpPrisma.role.update({
        where: { id: existingRole.id },
        data: { permissions: PROVIDER_STAFF_PERMISSIONS },
      });
      roleIds.push(existingRole.id);
    } else {
      const roleId = `role-${tenant.id}-${roleName}`;
      await idpPrisma.role.create({
        data: {
          id: roleId,
          tenantId: tenant.id,
          name: roleName,
          isSystem: true,
          permissions: PROVIDER_STAFF_PERMISSIONS,
        },
      });
      roleIds.push(roleId);
    }
  }

  // Provision each staff account
  for (const account of STAFF_ACCOUNTS) {
    let user = await idpPrisma.user.findFirst({
      where: {
        email: { equals: account.email, mode: "insensitive" },
        tenantId: tenant.id,
      },
      orderBy: { createdAt: "asc" },
    });

    if (!user) {
      user = await idpPrisma.user.create({
        data: {
          id: `usr-${randomUUID()}`,
          tenantId: tenant.id,
          email: account.email,
          passwordHash: account.passwordHash,
          firstName: account.firstName,
          lastName: account.lastName,
          status: "ACTIVE",
          failedLoginAttempts: 0,
          lockedUntil: null,
        },
      });
    } else {
      user = await idpPrisma.user.update({
        where: { id: user.id },
        data: {
          passwordHash: account.passwordHash,
          status: "ACTIVE",
          failedLoginAttempts: 0,
          lockedUntil: null,
          deletedAt: null,
        },
      });
    }

    // Assign all staff roles to user
    for (const roleId of roleIds) {
      await idpPrisma.userRole.upsert({
        where: { userId_roleId: { userId: user.id, roleId } },
        update: {},
        create: { userId: user.id, roleId },
      });
    }

    console.log(
      `provider realm ready — catalog tenant ${tenant.id}, principal ${user.id}, ${account.email} (${STAFF_ROLES.join(", ")})`,
    );
  }
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
