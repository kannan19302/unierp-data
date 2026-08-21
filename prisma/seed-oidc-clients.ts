/**
 * Registers the first-party OIDC clients: the ten platforms plus the Platform
 * Wizard.
 *
 * All of them are PUBLIC clients. None can keep a secret — the eight Next.js
 * apps authenticate from the browser, and the mobile and desktop shells ship
 * their bundle to the user's device, so any embedded secret is readable by
 * anyone who installs the app. They rely on PKCE plus exact redirect-URI
 * matching instead, which is what those mechanisms exist for.
 *
 * Idempotent: safe to re-run, and re-running is how registration changes (a new
 * redirect URI, a widened scope) reach an existing environment.
 *
 *   pnpm tsx prisma/seed-oidc-clients.ts
 */
import { idpPrisma } from "../src/index.js";

const BASE_SCOPES = [
  "openid",
  "profile",
  "email",
  "tenant",
  "offline_access",
];

const ERP_SCOPES = [...BASE_SCOPES, "erp.read", "erp.write"];

interface ClientSeed {
  clientId: string;
  name: string;
  platformCode: string | null;
  port?: number;
  /** Native clients redirect to a custom scheme, not an http origin. */
  nativeRedirect?: boolean;
  scopes: string[];
}

const CLIENTS: ClientSeed[] = [
  { clientId: "unierp-platform-wizard", name: "UniERP Platform Wizard", platformCode: null, port: 4000, scopes: BASE_SCOPES },
  { clientId: "unierp-marketing-site", name: "UniERP Marketing Site", platformCode: "P1", port: 4001, scopes: BASE_SCOPES },
  { clientId: "unierp-provider-admin-os", name: "Provider Admin OS", platformCode: "P2", port: 4002, scopes: BASE_SCOPES },
  { clientId: "unierp-tenant-apps", name: "Tenant Applications", platformCode: "P3", port: 4003, scopes: ERP_SCOPES },
  { clientId: "unierp-tenant-sites", name: "Tenant Websites", platformCode: "P4", port: 4004, scopes: BASE_SCOPES },
  { clientId: "unierp-web-studio", name: "Web Studio", platformCode: "P5", port: 4005, scopes: ERP_SCOPES },
  { clientId: "unierp-tenant-admin", name: "Tenant Admin Console", platformCode: "P6", port: 4006, scopes: ERP_SCOPES },
  { clientId: "unierp-marketplace", name: "UniERP Marketplace", platformCode: "P7", port: 4007, scopes: [...BASE_SCOPES, "marketplace.install"] },
  { clientId: "unierp-developer-platform", name: "Developer Platform", platformCode: "P8", port: 4008, scopes: ERP_SCOPES },
  { clientId: "unierp-mobile", name: "UniERP Mobile", platformCode: "P9", nativeRedirect: true, scopes: ERP_SCOPES },
  { clientId: "unierp-desktop", name: "UniERP Desktop", platformCode: "P10", nativeRedirect: true, scopes: ERP_SCOPES },
];

function redirectUris(seed: ClientSeed): string[] {
  if (seed.nativeRedirect) {
    return [
      // Custom scheme for the installed app.
      "unierp://auth/callback",
      // Loopback for desktop and for `flutter run` during development. The port
      // is deliberately fixed rather than ephemeral, because exact matching
      // leaves no room for a wildcard.
      "http://127.0.0.1:8765/auth/callback",
    ];
  }
  const origin = `http://localhost:${seed.port}`;
  return [
    `${origin}/auth/callback`,
    // The *.unierp.local hostnames the plan introduces so cookies stop relying
    // on localhost ignoring port numbers.
    `http://${seed.clientId.replace("unierp-", "")}.unierp.local/auth/callback`,
  ];
}

function postLogoutUris(seed: ClientSeed): string[] {
  // Everyone lands back on the wizard after signing out — it is the one page
  // that makes sense with no session.
  const wizard = "http://localhost:4000/";
  if (seed.nativeRedirect) return ["unierp://auth/logout", wizard];
  return [`http://localhost:${seed.port}/`, wizard];
}

async function main() {
  console.log(`Registering ${CLIENTS.length} first-party OIDC clients…`);

  for (const seed of CLIENTS) {
    const data = {
      name: seed.name,
      clientType: "PUBLIC",
      clientSecretHash: null,
      platformCode: seed.platformCode,
      isFirstParty: true,
      ownerTenantId: null,
      redirectUris: redirectUris(seed),
      postLogoutRedirectUris: postLogoutUris(seed),
      grantTypes: ["authorization_code", "refresh_token"],
      allowedScopes: seed.scopes,
      status: "ACTIVE",
    };

    await idpPrisma.oAuthClient.upsert({
      where: { clientId: seed.clientId },
      create: { clientId: seed.clientId, ...data },
      update: data,
    });

    console.log(
      `  ${seed.platformCode ?? "—".padEnd(3)}  ${seed.clientId.padEnd(28)} ${data.redirectUris[0]}`,
    );
  }

  const total = await idpPrisma.oAuthClient.count();
  console.log(`Done. ${total} client(s) registered.`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(async () => {
    await idpPrisma.$disconnect();
  });
