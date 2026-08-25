import type { PrismaClient } from "@prisma/client";
import {
  LEGACY_PROVIDER_REALM_TENANT_SLUG,
  PROVIDER_REALM_TENANT_ID,
  PROVIDER_REALM_TENANT_SLUG,
} from "@kannan19302/shared";

/**
 * Find or provision the single reserved provider identity realm.
 *
 * Older seeds independently created `platform-control-plane` and `provider`
 * tenants. Automatically choosing between two live realms would make staff
 * authority depend on seed order, so that state fails closed and requires an
 * explicit data migration. A lone legacy realm is safely renamed in place,
 * preserving every existing identity foreign key.
 */
export async function ensureProviderRealm(prisma: PrismaClient) {
  const candidates = await prisma.tenant.findMany({
    where: {
      slug: {
        in: [
          PROVIDER_REALM_TENANT_SLUG,
          LEGACY_PROVIDER_REALM_TENANT_SLUG,
        ],
      },
    },
    orderBy: { createdAt: "asc" },
  });

  if (candidates.length > 1) {
    throw new Error(
      "Multiple provider identity realms exist. Consolidate the provider and " +
        "platform-control-plane tenant records before provisioning staff authority.",
    );
  }

  const existing = candidates[0];
  if (existing) {
    return prisma.tenant.update({
      where: { id: existing.id },
      data: {
        name: "UniERP Provider Identity Realm",
        slug: PROVIDER_REALM_TENANT_SLUG,
        plan: "system",
        status: "SYSTEM",
        settings: { isControlPlane: true, isProviderRealm: true },
        onboardingComplete: true,
      },
    });
  }

  return prisma.tenant.create({
    data: {
      id: PROVIDER_REALM_TENANT_ID,
      name: "UniERP Provider Identity Realm",
      slug: PROVIDER_REALM_TENANT_SLUG,
      plan: "system",
      status: "SYSTEM",
      settings: { isControlPlane: true, isProviderRealm: true },
      onboardingComplete: true,
    },
  });
}
