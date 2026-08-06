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

// `prisma generate` parses the schema, and the schema reads env("DATABASE_URL").
// Without it the generator exits non-zero and npm fails the whole install — so
// `npm install @unerp/database` required a database URL to be present before you
// could even install the package that talks to the database.
//
// Generation does not connect to anything; it only needs the value to be
// syntactically valid. A placeholder lets the install finish, and the real URL
// is read at runtime as normal.
const env = {
  ...process.env,
  DATABASE_URL:
    process.env.DATABASE_URL ?? "postgresql://placeholder:placeholder@localhost:5432/placeholder",
};

const run = (cmd) => execSync(cmd, { cwd: root, stdio: "inherit", env });

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
  // Warn loudly; do not fail the install.
  //
  // Generation needs a working toolchain and network, and neither is guaranteed
  // wherever someone runs `npm install` — a locked-down CI image, an offline
  // machine, a transient registry error. Throwing here failed the entire
  // install, so a consumer could not even add this package to their project,
  // and npm's cleanup then left a half-removed directory that broke the next
  // attempt too. That is how `unierp-auth` became uninstallable.
  //
  // Importing without a generated client fails with a clear message of its own,
  // and `npx prisma generate` fixes it. A loud warning beats an install that
  // cannot complete.
  console.warn("\n  @unerp/database: prisma generate did not complete.");
  console.warn(`  ${String(error?.message ?? error).split("\n")[0]}`);
  console.warn("  Run `npx prisma generate` in this package before importing it.\n");
}
