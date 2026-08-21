/**
 * Grants the `sso.federation` feature (idp/src/modules/auth/sso-plan-gate.ts)
 * to every currently-seeded SaaSPlan whose name suggests it's the Enterprise
 * tier — there is no dedicated plan-tier catalog yet (that's W15's billing
 * engine), only whatever `prisma.saaSPlan` rows a given environment's seed.ts
 * happened to create. Matching by name rather than hardcoding an id keeps
 * this idempotent and safe to re-run against any seeded environment.
 *
 *   pnpm tsx prisma/seed-sso-feature.ts
 */
import { prisma } from "../src/index.js";

async function main() {
  const plans = await prisma.saaSPlan.findMany({
    where: { name: { contains: "Enterprise", mode: "insensitive" } },
  });

  if (plans.length === 0) {
    console.warn(
      "[seed-sso-feature] No plan with 'Enterprise' in its name found — nothing to grant. Run seed.ts first.",
    );
    return;
  }

  for (const plan of plans) {
    await prisma.saaSPlanFeature.upsert({
      where: { planId_featureKey: { planId: plan.id, featureKey: "sso.federation" } },
      create: {
        planId: plan.id,
        featureKey: "sso.federation",
        name: "Inbound SSO federation (SAML/OIDC)",
        description: "Tenant-configured SAML or OIDC sign-in against the tenant's own identity provider.",
        type: "BOOLEAN",
        isActive: true,
      },
      update: { isActive: true },
    });
    console.log(`[seed-sso-feature] Granted sso.federation to plan "${plan.name}" (${plan.id})`);
  }
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
