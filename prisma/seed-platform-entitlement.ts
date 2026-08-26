/**
 * Seeds the platform catalog and the baseline entitlement grants.
 *
 * Without this, /oidc/authorize has clients (from seed-oidc-clients.ts) that
 * reference platform codes no `Platform` row exists for, and W2's entitlement
 * resolver has nothing to resolve against — every request would be refused for
 * lack of data, which looks identical to a real access denial and is much
 * harder to diagnose.
 *
 * Idempotent: safe to re-run.
 *
 *   pnpm tsx prisma/seed-platform-entitlement.ts
 */
import { idpPrisma } from "../src/index.js";
import { prisma } from "../src/index.js";

interface PlatformSeed {
  code: string;
  name: string;
  port: number;
  audience: "INTERNAL" | "PUBLIC";
  requiresTenant: boolean;
  lifecycle: "ACTIVE" | "RETIRED";
  surfaceType: "USER_UI" | "NATIVE_CLIENT" | "OPERATIONS";
  isUserFacing: boolean;
  discoverability: "PUBLIC" | "ENTITLED" | "INTERNAL";
  category: "DISCOVER" | "OPERATIONS" | "WORK" | "BUILD";
  sortWeight: number;
  minimumAssurance?: "aal2" | "aal3";
}

const PLATFORMS: PlatformSeed[] = [
  { code: "P1", name: "Marketing Site", port: 4001, audience: "PUBLIC", requiresTenant: false, lifecycle: "ACTIVE", surfaceType: "USER_UI", isUserFacing: true, discoverability: "PUBLIC", category: "DISCOVER", sortWeight: 10 },
  { code: "P2", name: "Provider Control Center (PCC)", port: 4002, audience: "INTERNAL", requiresTenant: false, lifecycle: "ACTIVE", surfaceType: "OPERATIONS", isUserFacing: true, discoverability: "ENTITLED", category: "OPERATIONS", sortWeight: 20 },
  { code: "P3", name: "Tenant Applications", port: 4003, audience: "PUBLIC", requiresTenant: true, lifecycle: "ACTIVE", surfaceType: "USER_UI", isUserFacing: true, discoverability: "ENTITLED", category: "WORK", sortWeight: 30 },
  { code: "P4", name: "Tenant Websites", port: 4004, audience: "PUBLIC", requiresTenant: true, lifecycle: "ACTIVE", surfaceType: "USER_UI", isUserFacing: true, discoverability: "ENTITLED", category: "WORK", sortWeight: 40 },
  // P5 is RETIRED — Web Studio is now a pillar of P8, not a platform of its own.
  { code: "P5", name: "Web Studio (merged into P8)", port: 4005, audience: "PUBLIC", requiresTenant: true, lifecycle: "RETIRED", surfaceType: "USER_UI", isUserFacing: false, discoverability: "ENTITLED", category: "BUILD", sortWeight: 50 },
  { code: "P6", name: "Organization Control Center (OCC)", port: 4006, audience: "PUBLIC", requiresTenant: true, lifecycle: "ACTIVE", surfaceType: "USER_UI", isUserFacing: true, discoverability: "ENTITLED", category: "OPERATIONS", sortWeight: 60 },
  { code: "P7", name: "Marketplace", port: 4007, audience: "PUBLIC", requiresTenant: false, lifecycle: "ACTIVE", surfaceType: "USER_UI", isUserFacing: true, discoverability: "ENTITLED", category: "DISCOVER", sortWeight: 70 },
  { code: "P8", name: "Developer Platform", port: 4008, audience: "PUBLIC", requiresTenant: false, lifecycle: "ACTIVE", surfaceType: "USER_UI", isUserFacing: true, discoverability: "ENTITLED", category: "BUILD", sortWeight: 80 },
  { code: "P9", name: "Mobile", port: 4009, audience: "PUBLIC", requiresTenant: true, lifecycle: "ACTIVE", surfaceType: "NATIVE_CLIENT", isUserFacing: true, discoverability: "ENTITLED", category: "WORK", sortWeight: 90 },
  { code: "P10", name: "Desktop", port: 4010, audience: "PUBLIC", requiresTenant: true, lifecycle: "ACTIVE", surfaceType: "NATIVE_CLIENT", isUserFacing: true, discoverability: "ENTITLED", category: "WORK", sortWeight: 100 },
];

/**
 * Platforms every authenticated user reaches — the core "one account, every platform" promise.
 */
const BASELINE_TENANT_PLATFORMS = ["P1", "P2", "P3", "P4", "P6", "P7", "P8", "P9", "P10"];

const PLAN_GATED_PLATFORMS: string[] = [];

/** UniERP internal staff and admin roles reach the control plane. */
const PROVIDER_STAFF_ROLES = [
  "platform.admin",
  "platform.sre",
  "platform.support.l1",
  "platform.support.l2",
  "platform.billing",
  "platform.security",
  "SUPER_ADMIN",
  "Super Admin",
  "Admin",
  "admin",
  "Owner",
  "Platform Owner",
];

async function main() {
  console.log(`Seeding ${PLATFORMS.length} platforms…`);
  for (const p of PLATFORMS) {
    await idpPrisma.platform.upsert({
      where: { code: p.code },
      create: {
        code: p.code,
        name: p.name,
        port: p.port,
        baseUrl: `http://localhost:${p.port}`,
        audience: p.audience,
        requiresTenant: p.requiresTenant,
        lifecycle: p.lifecycle,
        surfaceType: p.surfaceType,
        isUserFacing: p.isUserFacing,
        discoverability: p.discoverability,
        category: p.category,
        sortWeight: p.sortWeight,
        minimumAssurance: p.minimumAssurance ?? null,
      },
      update: {
        name: p.name,
        port: p.port,
        baseUrl: `http://localhost:${p.port}`,
        audience: p.audience,
        requiresTenant: p.requiresTenant,
        lifecycle: p.lifecycle,
        surfaceType: p.surfaceType,
        isUserFacing: p.isUserFacing,
        discoverability: p.discoverability,
        category: p.category,
        sortWeight: p.sortWeight,
        minimumAssurance: p.minimumAssurance ?? null,
      },
    });
  }

  console.log("Granting baseline platform access…");
  for (const code of BASELINE_TENANT_PLATFORMS) {
    await idpPrisma.platformGrant.upsert({
      where: {
        id: await findOrPlaceholder("ROLE", "*", code, null),
      },
      create: { subjectType: "ROLE", subjectId: "*", platformCode: code, tenantId: null, effect: "ALLOW", reason: "baseline platform access" },
      update: { effect: "ALLOW", validFrom: null, validUntil: null, reason: "baseline platform access" },
    });
  }

  console.log("Granting provider-staff and admin access to all active platform surfaces…");
  for (const role of PROVIDER_STAFF_ROLES) {
    for (const platform of PLATFORMS.filter((entry) => entry.lifecycle === "ACTIVE")) {
      await idpPrisma.platformGrant.upsert({
        where: { id: await findOrPlaceholder("ROLE", role, platform.code, null) },
        create: { subjectType: "ROLE", subjectId: role, platformCode: platform.code, tenantId: null, effect: "ALLOW", reason: "staff/admin platform access" },
        update: { effect: "ALLOW", validFrom: null, validUntil: null, reason: "staff/admin platform access" },
      });
    }
  }

  // Explicit user-level grant for primary admin email if present
  const adminUsers = await idpPrisma.user.findMany({
    where: { email: { in: ["kannan19302@gmail.com", "admin@unierp.com"] } },
    select: { id: true, email: true, tenantId: true },
  });
  for (const u of adminUsers) {
    for (const platform of PLATFORMS.filter((entry) => entry.lifecycle === "ACTIVE")) {
      await idpPrisma.platformGrant.upsert({
        where: { id: await findOrPlaceholder("USER", u.id, platform.code, u.tenantId) },
        create: { subjectType: "USER", subjectId: u.id, platformCode: platform.code, tenantId: u.tenantId, effect: "ALLOW", reason: `direct admin grant for ${u.email}` },
        update: { effect: "ALLOW", validFrom: null, validUntil: null, reason: `direct admin grant for ${u.email}` },
      });
    }
  }

  const platformCount = await idpPrisma.platform.count();
  const grantCount = await idpPrisma.platformGrant.count();
  console.log(`Done. ${platformCount} platform(s), ${grantCount} grant(s).`);
}

async function findOrPlaceholder(
  subjectType: string,
  subjectId: string,
  platformCode: string,
  tenantId: string | null,
): Promise<string> {
  const existing = await idpPrisma.platformGrant.findFirst({
    where: { subjectType, subjectId, platformCode, tenantId },
  });
  return existing?.id ?? "00000000-0000-0000-0000-000000000000";
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
