// ─────────────────────────────────────────────────
// Database Package — Prisma Client Export
// ─────────────────────────────────────────────────

import { PrismaClient } from "./main-client/index.js";
import { PrismaClient as IdpPrismaClient } from "./idp-client/index.js";
import { getTenantSession } from "./tenant-context.js";
import { applyTenantScope, MODELS_WITHOUT_TENANT } from "./tenant-scope.js";
import { applySoftDeleteScope } from "./soft-delete.js";

// Prevent multiple Prisma Client instances in development
const globalForPrisma = globalThis as unknown as {
  prisma: unknown;
};

const basePrisma = new PrismaClient({
  log:
    process.env.NODE_ENV === "development"
      ? ["query", "error", "warn"]
      : ["error"],
});

function getModelPropertyName(modelName: string): string {
  if (!modelName) return "";
  return modelName.charAt(0).toLowerCase() + modelName.slice(1);
}

/**
 * Apply the tenant-context extension to a Prisma client.
 *
 * Factored out so the IdP client gets the identical treatment rather than a
 * second copy that drifts. `base` is the client the extension falls back to for
 * interactive-transaction plumbing — it must be the same unextended client the
 * extension is being applied to, or `_createItxClient` operates on the wrong
 * connection.
 */
function withTenantContext<T extends object>(base: T): T {
  return (base as unknown as { $extends: (ext: unknown) => T }).$extends(
    tenantContextExtension(base as unknown as ItxCapableClient),
  );
}

type ItxCapableClient = {
  $transaction: <R>(fn: (tx: Record<string, unknown>) => Promise<R>) => Promise<R>;
  _createItxClient?: (tx: unknown) => unknown;
};

const tenantContextExtension = (basePrisma: ItxCapableClient) => ({
  query: {
    $allModels: {
      async $allOperations({
        model,
        operation,
        args,
        query,
        ...rest
      }: {
        model: string;
        operation: string;
        args: unknown;
        query: (args: unknown) => Promise<unknown>;
      }) {
        // G.4: Apply soft-delete scope FIRST — all models with deletedAt get
        // deletedAt: null injected into their where clause, regardless of
        // tenant session. This prevents soft-deleted records from appearing
        // in any normal query or mutation.
        let scopedArgs = applySoftDeleteScope(model, operation, args);

        const session = getTenantSession();
        if (!session) {
          return query(scopedArgs);
        }

        // Models in MODELS_WITHOUT_TENANT have no tenantId column of their own
        // (e.g. UserRole, a join table) so they're exempt from where-clause
        // injection — but the RLS session GUC below must still be set
        // whenever a tenant session exists, because these models can still
        // `include` a relation into an RLS-protected tenant-scoped table
        // (e.g. UserRole -> Role). Skipping the GUC here would silently
        // return null/empty relations under the unerp_api runtime role.
        if (!MODELS_WITHOUT_TENANT.has(model)) {
          scopedArgs = applyTenantScope(
            model,
            operation,
            scopedArgs,
            session.tenantId,
          );
        }

        // Track C (#21): database-enforced RLS on ALL tenant-scoped tables.
        // Set app.current_tenant_id transaction-locally so the RLS policy
        // function current_tenant_id() returns the correct value for this
        // query's transaction. Uses $executeRaw (parameterized) to avoid
        // SQL injection in the tenant ID value.
        const execute = async (client: {
          $executeRaw: (
            strings: TemplateStringsArray,
            ...values: unknown[]
          ) => Promise<unknown>;
        }) => {
          await client.$executeRaw`SELECT set_config('app.current_tenant_id', ${session.tenantId}, true)`;
        };

        const transaction = (
          (rest as Record<string, unknown>).__internalParams as
            | { transaction?: { kind: string } }
            | undefined
        )?.transaction;

        if (
          transaction?.kind === "itx" &&
          typeof (
            basePrisma as unknown as {
              _createItxClient: (tx: unknown) => unknown;
            }
          )._createItxClient === "function"
        ) {
          const itxClient = (
            basePrisma as unknown as {
              _createItxClient: (tx: unknown) => {
                $executeRaw: (
                  strings: TemplateStringsArray,
                  ...values: unknown[]
                ) => Promise<unknown>;
              };
            }
          )._createItxClient(transaction);
          await execute(itxClient);
          return query(scopedArgs);
        }

        return basePrisma.$transaction(async (tx: Record<string, unknown>) => {
          await execute(tx as unknown as Parameters<typeof execute>[0]);
          const modelProp = getModelPropertyName(model);
          const txModel = (
            tx as unknown as Record<
              string,
              Record<string, (args: unknown) => Promise<unknown>>
            >
          )[modelProp];
          if (!txModel) {
            throw new Error(
              `Model ${modelProp} not found on transaction client`,
            );
          }
          const queryFn = txModel[operation];
          if (!queryFn) {
            throw new Error(
              `Operation ${operation} not found on model ${modelProp}`,
            );
          }
          return queryFn(scopedArgs);
        });
      },
    },
  },
});

export const prisma = withTenantContext(basePrisma) as unknown as PrismaClient;

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.prisma = prisma;
}

export type PrismaClientType = typeof prisma;
export { PrismaClient };
export { Prisma } from "./main-client/index.js";
export * from "./main-client/index.js";
export {
  getTenantSession,
  runWithTenantSession,
  // Exported for test harnesses, which need to seed a tenant session for a whole
  // file via `enterWith` rather than wrapping every call in runWithTenantSession.
  // Application code must use runWithTenantSession; the TenantInterceptor does.
  tenantLocalStorage,
} from "./tenant-context.js";
export { applyTenantScope, MODELS_WITHOUT_TENANT } from "./tenant-scope.js";
export {
  applySoftDeleteScope,
  SOFT_DELETE_ENABLED_MODELS,
} from "./soft-delete.js";
export { encryptField, decryptField, isEncrypted } from "./encryption.js";
export {
  StaleWriteError,
  RecordNotFoundForUpdateError,
  updateWithVersionGuard,
  type VersionedDelegate,
  type VersionGuardTarget,
} from "./optimistic-locking.js";

import { Injectable, OnModuleInit, OnModuleDestroy } from "@nestjs/common";

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}

export { IdpPrismaClient };
@Injectable()
export class IdpPrismaService
  extends IdpPrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  async onModuleInit() {
    await this.$connect();
  }
  async onModuleDestroy() {
    await this.$disconnect();
  }
}
/**
 * The IdP client carries the same tenant-context extension as the main one.
 *
 * It used to be a bare `new IdpPrismaClient()`, which meant
 * `runWithTenantSession` had no effect on it: the session is held in an
 * AsyncLocalStorage and only the **extension** turns it into
 * `set_config('app.current_tenant_id', …)`. Every `idpPrisma` query therefore
 * reached Postgres with no tenant GUC.
 *
 * That was invisible for as long as the application connected as the database
 * owner, because the owner is a superuser and a superuser bypasses RLS
 * outright. Running as `unerp_api` (NOBYPASSRLS) — which § 5.1 requires, and
 * which the container stack was the first thing to actually do — every
 * tenant-scoped read through this client returned nothing. Login failed with
 * "Invalid credentials" against a user row that was present, ACTIVE and
 * correctly hashed, because RLS was hiding it from the query that looked for
 * it.
 *
 * § 5.2 gives the IdP its own realm; it does not exempt it from § 5.1.
 */
export const idpPrisma = withTenantContext(
  new IdpPrismaClient(),
) as unknown as IdpPrismaClient;

export { Prisma as IdpPrismaTypes } from "./idp-client/index.js";
export * as IdpModels from "./idp-client/index.js";
