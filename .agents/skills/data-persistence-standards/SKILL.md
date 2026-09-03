---
name: data-persistence-standards
description: Authoritative standards, architectural boundaries, coding anatomy, and verification gates for data.
version: 1.0.0
author: UniERP Architecture Governance
---

# UniERP Database & Data Persistence Engine — AI Agent Guidance & Project Skill

This skill governs all code modification, analysis, and testing within `data` (**Layer L2: Runtime**). Every AI agent and software engineer working in this repository MUST follow these rules without exception.

---

## 🏛️ 1. Architectural Position & Boundary Rules

- **Repository**: `data`
- **Layer**: **L2 (Runtime)**
- **Package Identity**: `@kannan19302/database`
- **Allowed Inbound Callers**: L3 (api, idp)
- **Allowed Outbound Dependencies**: @kannan19302/contracts (L0); L1 packages
- **STRICTLY FORBIDDEN DEPENDENCIES**:
  - ❌ Layers L3-L7
  - ❌ HTTP controllers
  - ❌ UI components

> **Unidirectional Rule**: You may ONLY import published artifacts from strictly lower layers. Sibling imports within the same layer are prohibited unless mediated through L0 contracts.

---

## 🎯 2. The Platform Goal & Repository Mandate

> **Platform North Star Goal**:  
> "Build the world's premier autonomous, multi-tenant Enterprise SaaS Operating System: 100% Zero-Trust Multi-Tenant Isolation, Absolute Decimal(19,4) Numeric Precision, Atomic Durable Audit Logging, Sub-100ms P99 Latency, and Strata Workbench High-Density UI."

### Repository Responsibility Mandate
Authoritative Prisma schemas (44 schemas), PostgreSQL migrations, connection pooling, and universal Row-Level Security (RLS).

---

## 📐 3. Repository-Specific Coding Standards

### Mandatory Database Persistence Standards
1. **Universal RLS**: Every table with `tenantId` MUST have an explicit, restrictive RLS policy.
2. **Exact Decimal Math**: Financial and stock fields MUST use `@db.Decimal(19,4)`. Zero `Float` permitted.
3. **Immutable Migrations**: Never mutate existing committed migrations. Always author new migrations.

---

## 🛡️ 4. Mandatory Pre-Commit Verification Gate

Before submitting or reporting completion on any change in this repository, run and verify:

```bash
pnpm test && pnpm build
```

All tests must pass with 0 failures and 0 type errors.
