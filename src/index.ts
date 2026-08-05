// ─────────────────────────────────────────────────
// Database Package — Prisma Client Export
// ─────────────────────────────────────────────────

import { PrismaClient } from "@prisma/client";
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

export const prisma = basePrisma.$extends({
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

        return basePrisma.$transaction(async (tx: {
          $executeRaw: (
            strings: TemplateStringsArray,
            ...values: unknown[]
          ) => Promise<unknown>;
        }) => {
          await execute(tx);
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
}) as unknown as PrismaClient;

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.prisma = prisma;
}

export type PrismaClientType = typeof prisma;
export { PrismaClient };
export type { Prisma } from "@prisma/client";
export * from "@prisma/client";
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
const baseIdpPrisma = new IdpPrismaClient();

/**
 * The IdP client sets the RLS tenant GUC, exactly as the main client does.
 *
 * Without this it set nothing, and the identity tables it serves — user_sessions
 * above all — carry RLS with ENABLE + FORCE while the application role is
 * NOBYPASSRLS. Every query returned zero rows rather than an error, so
 * JwtAuthGuard's session-revocation check found no session and rejected EVERY
 * authenticated request with "Session has been revoked or expired" while the row
 * sat in the table, active and unexpired.
 *
 * That made authentication impossible against a correctly-secured database. It
 * only appeared to work where RLS was unenforced or the connection was the table
 * owner — which is to say, it worked in exactly the environments where the
 * isolation guarantee was not real.
 *
 * Unlike the main client this deliberately does NOT inject tenantId into the
 * where clause: the IdP schema's models are keyed differently and some identity
 * lookups are legitimately by primary key. The GUC is what RLS reads, and RLS is
 * the layer that constitutes proof.
 */
export const idpPrisma = baseIdpPrisma.$extends({
  query: {
    async $allOperations({ model, operation, args, query }) {
      const session = getTenantSession();
      if (!session || !model) return query(args);

      // set_config(..., true) is TRANSACTION-local. Issued on its own it applies
      // to the implicit transaction of that one statement and is gone before the
      // next query runs — so the GUC was being set and immediately discarded,
      // and RLS still saw no tenant. The setting and the query have to share one
      // transaction, which is why the operation is re-issued on the transaction
      // client rather than passed through.
      return baseIdpPrisma.$transaction(async (tx) => {
        await tx.$executeRaw`SELECT set_config('app.current_tenant_id', ${session.tenantId}, true)`;
        const delegate = (tx as unknown as Record<string, unknown>)[
          getModelPropertyName(model)
        ] as Record<string, (a: unknown) => Promise<unknown>> | undefined;
        if (!delegate?.[operation]) return query(args);
        return delegate[operation](args);
      });
    },
  },
}) as unknown as typeof baseIdpPrisma;

export { Prisma as IdpPrismaTypes } from "./idp-client/index.js";
export * as IdpModels from "./idp-client/index.js";
