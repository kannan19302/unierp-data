import { describe, expect, it, vi } from "vitest";
import {
  LEGACY_PROVIDER_REALM_TENANT_SLUG,
  PROVIDER_REALM_TENANT_ID,
  PROVIDER_REALM_TENANT_SLUG,
} from "@kannan19302/shared";
import { ensureProviderRealm } from "../prisma/provider-realm";
import { PROVIDER_STAFF_PERMISSIONS } from "../prisma/seed-provider-realm";

function clientWith(candidates: unknown[]) {
  return {
    tenant: {
      findMany: vi.fn().mockResolvedValue(candidates),
      update: vi.fn().mockImplementation(({ data }) =>
        Promise.resolve({ id: "existing", ...data }),
      ),
      create: vi.fn().mockImplementation(({ data }) => Promise.resolve(data)),
    },
  };
}

describe("canonical provider identity realm", () => {
  it("creates the one canonical system tenant for a fresh environment", async () => {
    const prisma = clientWith([]);

    const realm = await ensureProviderRealm(prisma as never);

    expect(prisma.tenant.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        id: PROVIDER_REALM_TENANT_ID,
        slug: PROVIDER_REALM_TENANT_SLUG,
        status: "SYSTEM",
        plan: "system",
        settings: { isControlPlane: true, isProviderRealm: true },
      }),
    });
    expect(realm.slug).toBe(PROVIDER_REALM_TENANT_SLUG);
  });

  it("renames a lone legacy realm in place so identity references survive", async () => {
    const prisma = clientWith([
      {
        id: "platform",
        slug: LEGACY_PROVIDER_REALM_TENANT_SLUG,
        createdAt: new Date(0),
      },
    ]);

    await ensureProviderRealm(prisma as never);

    expect(prisma.tenant.update).toHaveBeenCalledWith({
      where: { id: "platform" },
      data: expect.objectContaining({
        slug: PROVIDER_REALM_TENANT_SLUG,
        status: "SYSTEM",
      }),
    });
    expect(prisma.tenant.create).not.toHaveBeenCalled();
  });

  it("fails closed when both historical provider realms exist", async () => {
    const prisma = clientWith([
      { id: "platform", slug: LEGACY_PROVIDER_REALM_TENANT_SLUG },
      { id: "tnt-provider", slug: PROVIDER_REALM_TENANT_SLUG },
    ]);

    await expect(ensureProviderRealm(prisma as never)).rejects.toThrow(
      "Multiple provider identity realms exist",
    );
    expect(prisma.tenant.update).not.toHaveBeenCalled();
    expect(prisma.tenant.create).not.toHaveBeenCalled();
  });

  it("seeds every canonical PCC app entry permission without a PCC wildcard", () => {
    const pccAppEntries = PROVIDER_STAFF_PERMISSIONS.filter(
      (permission) =>
        permission.startsWith("pcc.") && permission.endsWith(".access"),
    );

    expect(pccAppEntries).toHaveLength(22);
    expect(new Set(pccAppEntries).size).toBe(22);
    expect(PROVIDER_STAFF_PERMISSIONS).not.toContain("pcc.*");
  });
});
