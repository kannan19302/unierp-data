// Generate the Prisma clients at install time.
//
// @unerp/database ships prisma/ but not the generated clients: they are
// platform-specific binaries, and a published artifact that pins a query engine
// to whoever ran `npm publish` is wrong. So the consumer generates them — and
// must, because dist/index.js imports both.
//
// There are TWO, not one. § 5.2 gives each plane its own identity realm, so the
// IdP has its own datasource and its own client. Generating only the main schema
// compiles perfectly and then dies at import with
// `Cannot find module './idp-client/index.js'`.
//
// The generator writes to src/idp-client, but dist/index.js requires
// './idp-client/index.js' relative to ITSELF, so the output is copied alongside
// the compiled entrypoint.
import { execSync } from "node:child_process";
import { existsSync, rmSync, cpSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const run = (cmd) => execSync(cmd, { cwd: root, stdio: "inherit" });

try {
  if (existsSync(join(root, "prisma", "schema"))) {
    run("npx prisma generate --schema prisma/schema");
  }

  const idpSchema = join(root, "prisma", "idp-schema.prisma");
  if (existsSync(idpSchema)) {
    run("npx prisma generate --schema prisma/idp-schema.prisma");
    const from = join(root, "src", "idp-client");
    const to = join(root, "dist", "idp-client");
    if (existsSync(from) && existsSync(join(root, "dist"))) {
      rmSync(to, { recursive: true, force: true });
      cpSync(from, to, { recursive: true });
    }
  }
} catch (error) {
  console.error("\n@unerp/database: prisma generate failed.");
  console.error("The package cannot be imported until this succeeds.\n");
  throw error;
}
