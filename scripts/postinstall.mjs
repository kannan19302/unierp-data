// Generate the Prisma clients at install time.
//
// @kannan19302/database ships prisma/ but not the generated clients: they are
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
import { createRequire } from "node:module";
import { existsSync, rmSync, cpSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

// `prisma generate` parses the schema, and the schema reads env("DATABASE_URL").
// Without it the generator exits non-zero and npm fails the whole install — so
// `npm install @kannan19302/database` required a database URL to be present before you
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

// Resolve the Prisma CLI from this package's own dependency tree — never `npx`.
//
// `npx prisma` looks for a local binary and, not finding one, **downloads the
// latest from the network**. Installed as a dependency of another project this
// package has no devDependencies of its own, so `npx` fetched Prisma 7.9.1
// against a schema written for 6.x and failed validation:
//
//   error: The datasource property `url` is no longer supported in schema files
//
// The install then completed "successfully" with no generated client, and the
// consumer failed 2,323 times at typecheck on missing model types. A build step
// whose tool version is decided by whatever the registry published this morning
// is not a build step. `prisma` is a runtime dependency of this package for
// exactly this reason, and this resolves the binary it installed.
const prismaBin = (() => {
  const local = join(root, "node_modules", ".bin", "prisma");
  if (existsSync(local) || existsSync(`${local}.cmd`)) return JSON.stringify(local);
  try {
    // Hoisted into the consumer's tree, which is the usual npm layout.
    const pkg = createRequire(import.meta.url).resolve("prisma/package.json");
    return JSON.stringify(join(dirname(pkg), "build", "index.js"));
  } catch {
    return null;
  }
})();

const run = (args) => {
  if (!prismaBin) throw new Error("the prisma CLI is not resolvable from this package");
  const cmd = prismaBin.endsWith('index.js"')
    ? `node ${prismaBin} ${args}`
    : `${prismaBin} ${args}`;
  execSync(cmd, { cwd: root, stdio: "inherit", env });
};

try {
  if (existsSync(join(root, "prisma", "schema"))) {
    run("generate --schema prisma/schema");
    const from = join(root, "src", "main-client");
    const to = join(root, "dist", "main-client");
    if (existsSync(from) && existsSync(join(root, "dist"))) {
      rmSync(to, { recursive: true, force: true });
      cpSync(from, to, { recursive: true });
    }
  }

  const idpSchema = join(root, "prisma", "idp-schema.prisma");
  if (existsSync(idpSchema)) {
    run("generate --schema prisma/idp-schema.prisma");
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
  console.warn("\n  @kannan19302/database: prisma generate did not complete.");
  console.warn(`  ${String(error?.message ?? error).split("\n")[0]}`);
  console.warn("  Run `npx prisma generate` in this package before importing it.\n");
}
