    <!-- UniERP-Agent-Protocol: 1.1.0 -->
    # data agent rules

    This is the only repository agent instruction file. Read [the workspace entrypoint](../AGENTS.md),
    the [canonical protocol](../platform/docs/standards/AI_AGENT_DEVELOPMENT_PROTOCOL.md),
    the enterprise brain, applicable accepted ADRs and the owning platform requirements before
    material work. Follow authority precedence; this file narrows implementation behavior only.
    If a required authority is missing, stop before mutation.

    **Layer:** L2. **Accountable platform:** PLT-BIZ. **Scope:** PostgreSQL schema, migrations and persistence contracts.
    Resolve actual dependencies, packages and scripts from current manifests and the platform catalog.
    Preserve unrelated changes. Define numbered acceptance criteria and a knowledge delta before editing.
    For coordinated changes, publish the change contract, validate upstream first, and hand off
    to downstream consumers with exact evidence.

    ## Repository rules

    - Use new immutable migrations and expand/backfill/contract. Never reset or rewrite applied migrations against shared or unknown data.
- Enforce tenant scope in service logic and ENABLE plus FORCE RLS. Prove tenant A, tenant B and no-context behavior with a NOBYPASSRLS role.
- Preserve decimal money, units, constraints, indexes, audit and atomic outbox semantics; rehearse compatibility and recovery.

    ## Verification

    Run applicable commands from this repository, plus risk-specific contract, security, data,
    accessibility, integration, migration or release gates required by the canonical protocol:
    pnpm db:generate; pnpm typecheck; pnpm lint; pnpm test; pnpm build; node ../platform/workspace/scripts/check-layer.mjs

    A command's presence here is not proof that it ran. Report exact results, failures and NOT RUN
    reasons; review the diff; then follow the canonical status and source-control procedure.
