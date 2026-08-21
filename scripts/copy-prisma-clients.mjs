#!/usr/bin/env node
/**
 * Copies the generated Prisma client output into dist/.
 *
 * `prisma generate` writes .js/.d.ts files directly to src/*-client — they are
 * generated output, not TypeScript source, so `tsc` (which only emits from
 * .ts/.tsx it compiles) never copies them into dist/. Without this step,
 * dist/idp-client silently goes stale the moment the schema changes: it still
 * contains whichever models existed at the last manual copy, `tsc` reports no
 * error because the *declared* types still resolve, and every consumer sees
 * "Property 'x' does not exist" for a model that has existed in the schema for
 * some time. That is exactly what happened when Platform/PlatformGrant/
 * AgentDefinition/AgentDelegation were added in W2 — the schema, migration and
 * generated src/idp-client were all correct; only dist/idp-client lagged.
 */
import { cpSync, existsSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = fileURLToPath(new URL("..", import.meta.url));
const clients = ["idp-client"]; // add further generator outputs here as they appear

for (const client of clients) {
  const src = path.join(root, "src", client);
  const dest = path.join(root, "dist", client);
  if (!existsSync(src)) {
    console.warn(`[copy-prisma-clients] ${src} not found — skipping ${client}`);
    continue;
  }
  rmSync(dest, { recursive: true, force: true });
  cpSync(src, dest, { recursive: true });
  console.log(`[copy-prisma-clients] ${client} -> dist/${client}`);
}
