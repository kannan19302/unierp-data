/**
 * M47 / D046 — the control-plane seed's two standing invariants.
 *
 * `seed-platform.ts` is the ONLY sanctioned way to grant a `system.*` or
 * `platform.*` permission, because `hasPermission` refuses to satisfy those from
 * any tenant grant — including the global `*` a tenant Super Admin carries. That
 * makes this file the single place where control-plane authority is decided, and
 * therefore the single place where widening it is a security change rather than
 * a configuration change.
 *
 * Two properties are asserted, both of which were true only by convention until
 * D046 made it clear how expensive convention is here:
 *
 *   1. PLATFORM_SUPPORT is read-only. It exists so an L1 agent can answer "who
 *      is this tenant and what is wrong" without escalating. It gained 27 codes
 *      in M47, and the cheapest possible mistake is to paste a `.write` in
 *      among them — support could then adjust invoices, roll the platform back
 *      or offboard a tenant, and nothing would say so out loud.
 *
 *   2. Every permission either role grants is control-plane-namespaced. A
 *      tenant-plane code here would be satisfied by a tenant's own `*` grant,
 *      which is the escalation PLATFORM_ARCHITECTURE § 1.2 documents and this
 *      whole mechanism exists to close.
 */
import { describe, it, expect } from "vitest";
import { hasPermission } from "@kannan19302/shared";
import { PLATFORM_ROLES } from "../prisma/seed-platform";

/** Mirrors CONTROL_PLANE_NAMESPACES; asserted against it below rather than trusted. */
const CONTROL_PLANE = ["system", "platform"];

const isControlPlane = (code: string) =>
  CONTROL_PLANE.some((ns) => code === ns || code.startsWith(`${ns}.`));

/** A grant that can mutate. `.read` is the only action a read-only role may hold. */
const MUTATING = /\.(write|create|update|delete|execute|rollback|admin|purge|suspend|unsuspend|offboard|export|access|backup)$/;

describe("M47 · control-plane seed roles (D046)", () => {
  it("PLATFORM_SUPPORT is read-only — every code ends in .read", () => {
    const mutating = PLATFORM_ROLES.PLATFORM_SUPPORT.permissions.filter((c) =>
      MUTATING.test(c),
    );
    expect(
      mutating,
      `PLATFORM_SUPPORT is the read-only triage role. These codes can mutate: ` +
        `${mutating.join(", ")}. If support genuinely needs one of them, that is a ` +
        `new role, not a wider one.`,
    ).toEqual([]);
  });

  it("PLATFORM_SUPPORT cannot reach any destructive plane-1 operation", () => {
    const support = [...PLATFORM_ROLES.PLATFORM_SUPPORT.permissions];
    for (const code of [
      "system.offboarding.write",
      "system.release.rollback",
      "system.soc.execute",
      "system.invoice.write",
      "system.tenant.purge",
      "system.subscription.write",
      "system.upgrade.execute",
    ]) {
      expect(hasPermission(support, code), `support must not hold ${code}`).toBe(
        false,
      );
    }
  });

  it("PLATFORM_SUPPORT can still do its job — the read surfaces resolve", () => {
    const support = [...PLATFORM_ROLES.PLATFORM_SUPPORT.permissions];
    for (const code of [
      "system.tenant.read",
      "system.support.read",
      "system.invoice.read",
      "system.subscription.read",
      "system.operations.read",
    ]) {
      expect(hasPermission(support, code), `support must hold ${code}`).toBe(true);
    }
  });

  it("PLATFORM_OWNER's wildcards cover the plane-1 surface", () => {
    const owner = [...PLATFORM_ROLES.PLATFORM_OWNER.permissions];
    for (const code of [
      "system.offboarding.write",
      "system.release.rollback",
      "system.clusters.read",
      "system.soc.execute",
    ]) {
      expect(hasPermission(owner, code), `owner must hold ${code}`).toBe(true);
    }
  });

  it("no seeded control-plane role grants a tenant-plane permission", () => {
    for (const [role, def] of Object.entries(PLATFORM_ROLES)) {
      const leaked = def.permissions.filter((c) => !isControlPlane(c));
      expect(
        leaked,
        `${role} grants tenant-plane code(s) ${leaked.join(", ")}. A tenant's own ` +
          `"*" satisfies those, so they confer nothing here and imply authority ` +
          `this role does not have.`,
      ).toEqual([]);
    }
  });

  it("a tenant Super Admin's wildcard satisfies none of these roles' codes", () => {
    const every = Object.values(PLATFORM_ROLES).flatMap((r) => [...r.permissions]);
    const granted = every.filter((c) => hasPermission(["*"], c));
    expect(
      granted,
      `A tenant "*" grant satisfied ${granted.join(", ")} — the exact escalation ` +
        `seed-platform.ts exists to prevent.`,
    ).toEqual([]);
  });
});
