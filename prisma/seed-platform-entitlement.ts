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
}

const PLATFORMS: PlatformSeed[] = [
  { code: "P1", name: "Marketing Site", port: 4001, audience: "PUBLIC", requiresTenant: false },
  { code: "P2", name: "Provider Admin OS", port: 4002, audience: "INTERNAL", requiresTenant: false },
  { code: "P3", name: "Tenant Applications", port: 4003, audience: "PUBLIC", requiresTenant: true },
  { code: "P4", name: "Tenant Websites", port: 4004, audience: "PUBLIC", requiresTenant: true },
  // P5 is RETIRED — Web Studio is now a pillar of P8, not a platform of its own.
  // The row stays so the `unierp-web-studio` OIDC client keeps a valid
  // platformCode and existing :4005 bookmarks resolve; the app on that port is
  // a path-preserving redirect to :4008. It is granted to nobody (see
  // PLAN_GATED_PLATFORMS below), so it no longer appears in the wizard.
  { code: "P5", name: "Web Studio (merged into P8)", port: 4005, audience: "PUBLIC", requiresTenant: true },
  { code: "P6", name: "Tenant Admin Console", port: 4006, audience: "PUBLIC", requiresTenant: true },
  { code: "P7", name: "Marketplace", port: 4007, audience: "PUBLIC", requiresTenant: false },
  { code: "P8", name: "Developer Platform", port: 4008, audience: "PUBLIC", requiresTenant: false },
  { code: "P9", name: "Mobile", port: 4009, audience: "PUBLIC", requiresTenant: true },
  { code: "P10", name: "Desktop", port: 4010, audience: "PUBLIC", requiresTenant: true },
];

/**
 * Platforms every authenticated tenant user reaches without any plan
 * upgrade — the core "one account, every tenant platform" promise the wizard
 * exists to deliver, not something a customer has to unlock. P5 is absent
 * because it no longer exists as a platform (see PLAN_GATED_PLATFORMS); what
 * the revenue model actually gates now lives inside a platform, not in front
 * of one.
 */
const BASELINE_TENANT_PLATFORMS = ["P3", "P4", "P6", "P7", "P8", "P9", "P10"];

/**
 * Platforms a paid plan unlocks. **Empty, and correctly so.**
 *
 * P5 (Web Studio) was the only entry. It was plan-gated in this comment for a
 * long time while no PLAN grant was ever seeded, so `platform_grants` held ROLE
 * rows only, `tenantPlanGrantsPlatform` could never return true, and P5 was
 * unreachable for every tenant on every plan — signing in to :4005 returned
 * `access_denied`, indistinguishable from the platform being withheld
 * deliberately.
 *
 * That is now moot: Web Studio has been merged into P8 as a pillar, and P8 is
 * a baseline platform. The gate that actually belongs on website building is a
 * PERMISSION on the `/builder/web` and `/builder/sites` routes inside P8, not
 * an entitlement on a whole platform — a feature gate should not be able to
 * make an entire sign-in fail.
 *
 * Leave this array empty rather than deleting it: the plan-gating mechanism
 * itself is sound and the next paid platform will need it.
 */
const PLAN_GATED_PLATFORMS: string[] = [];

/** UniERP internal staff roles reach the control plane. Mirrors PolicyEngine's CONTROL_PLANE_ROLE. */
const PROVIDER_STAFF_ROLES = [
  "platform.admin",
  "platform.sre",
  "platform.support.l1",
  "platform.support.l2",
  "platform.billing",
  "platform.security",
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
      },
      update: {
        name: p.name,
        port: p.port,
        baseUrl: `http://localhost:${p.port}`,
        audience: p.audience,
        requiresTenant: p.requiresTenant,
      },
    });
  }

  console.log("Granting baseline tenant-platform access…");
  for (const code of BASELINE_TENANT_PLATFORMS) {
    // subjectId "*" is the tenant-agnostic "every tenant user" grant; the
    // entitlement resolver treats it as a wildcard ROLE match rather than a
    // literal role name, mirroring how the existing `["*"]` permission
    // wildcard already works elsewhere in this codebase.
    await idpPrisma.platformGrant.upsert({
      where: {
        // The DB unique index is (subjectType, subjectId, platformCode,
        // COALESCE(tenantId,'')); Prisma has no compound-expression unique
        // input for a COALESCE index, so this upsert keys on a find first.
        id: await findOrPlaceholder("ROLE", "*", code, null),
      },
      create: { subjectType: "ROLE", subjectId: "*", platformCode: code, tenantId: null },
      update: {},
    });
  }

  // Driven by the plans actually present rather than a hardcoded id: plan ids
  // are environment data (this machine has one, `plan-business-e2e`), so a
  // literal here would seed a grant that matches nothing anywhere else. Free
  // tiers stay excluded — the point of the gate is that a paid plan opens it.
  console.log("Granting plan-gated platform access…");
  const paidPlans = await prisma.saaSPlan.findMany({
    where: { status: "ACTIVE", NOT: { name: { in: ["Free", "free"] } } },
    select: { id: true, name: true },
  });
  for (const plan of paidPlans) {
    for (const code of PLAN_GATED_PLATFORMS) {
      await idpPrisma.platformGrant.upsert({
        where: { id: await findOrPlaceholder("PLAN", plan.id, code, null) },
        create: { subjectType: "PLAN", subjectId: plan.id, platformCode: code, tenantId: null },
        update: {},
      });
    }
    console.log(
      `  ${plan.name} (${plan.id}) -> ${PLAN_GATED_PLATFORMS.join(", ") || "(none)"}`,
    );
  }

  // Removing a code from PLAN_GATED_PLATFORMS is not enough on its own: every
  // write above is an upsert, so a grant seeded by an EARLIER run survives a
  // later run that no longer creates it. P5 was plan-gated when this seed last
  // ran against a live database, and leaving those rows behind would keep a
  // retired platform in the wizard while the source said it was gone — the
  // exact kind of claim that outlives its mechanism.
  const staleGrants = await idpPrisma.platformGrant.deleteMany({
    where: {
      subjectType: "PLAN",
      ...(PLAN_GATED_PLATFORMS.length > 0
        ? { platformCode: { notIn: PLAN_GATED_PLATFORMS } }
        : {}),
    },
  });
  if (staleGrants.count > 0) {
    console.log(
      `  removed ${staleGrants.count} PLAN grant(s) for platforms that are no longer plan-gated`,
    );
  }

  console.log("Granting provider-staff access to the control plane (P2)…");
  for (const role of PROVIDER_STAFF_ROLES) {
    await idpPrisma.platformGrant.upsert({
      where: { id: await findOrPlaceholder("ROLE", role, "P2", null) },
      create: { subjectType: "ROLE", subjectId: role, platformCode: "P2", tenantId: null },
      update: {},
    });
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
  // A non-existent id makes Prisma's upsert fall through to `create`; a real
  // id makes it a no-op `update: {}` against the row already there.
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
