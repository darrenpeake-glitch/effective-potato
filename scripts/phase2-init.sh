#!/usr/bin/env bash
set -euo pipefail

mkdir -p docs

cat > docs/PHASE_2_BRIEF.md <<'MD'
# Phase 2 Brief — Domain Expansion (Low-Risk)

## Objective
Expand product capability in a way that **does not weaken** the Phase 1 guarantees:
- Fail-closed tenant isolation via RLS
- Auth context guards (`app.user_id`, `app.org_id`) enforced consistently
- Server/admin-only writes where required (e.g., audit log)
- Test harness + CI verifying security invariants

Phase 2 is **feature delivery under the Phase 1 security model** (no shortcuts, no bypass).

## Scope (In)
1) **Select first domain surface** (see “Recommended first surface” below) and implement:
   - Schema + migrations
   - RLS policies aligned with existing guard functions
   - Repo functions (server/admin vs app/tenant)
   - Integration tests (happy path + negative cases)
2) **Operational hardening**
   - Scripts to set env, run migrations, and run tests deterministically
   - Ensure db:migrate uses explicit URL (no implicit env)
   - Ensure app role has least privilege; no table ownership assumptions

## Out of Scope (Not in Phase 2)
- Billing, invoicing, payments, subscriptions
- Complex workflow states and automations
- Multi-tenant reporting across orgs
- Performance optimisations beyond basic indexing

## Security & Data Model Principles (Non-Negotiable)
- RLS is the primary isolation boundary
- “Fail-closed” means:
  - Missing/invalid context rejects access or yields empty by design (consistent per table)
  - No accidental “read everything” states
- Admin/server writes only for:
  - Audit append
  - Org creation & membership provisioning (if you keep that server-side)

## Recommended First Surface (Low-Risk)
**Customer Directory + Vehicles (read-heavy, low coupling)**
- Adds immediate product value
- Minimal coupling to financial/workflow subsystems
- Cleanly models tenant isolation: everything is `org_id` scoped
- Easy to test: member vs non-member, cross-tenant, invalid context

Deliverables:
- `customers` table (org-scoped)
- `vehicles` table (org-scoped, optional customer relation)
- RLS policies: org member can CRUD within org only
- Repo + tests for:
  - member can list/create/update within org
  - non-member sees empty and cannot write
  - cross-tenant blocked even with manipulated `app.org_id`

## Acceptance Criteria
- `pnpm test` green
- `pnpm typecheck` green
- Fresh DB: `pnpm test:db` runs migrations + full test suite deterministically
- New domain tests include:
  - positive + negative cases
  - cross-tenant isolation tests
  - fail-closed context tests

## Work Plan (Suggested)
1) Choose surface (default: customers+vehicles)
2) Schema + migrations + indexes
3) RLS policies + guard usage
4) Repo layer
5) Integration tests
6) Wiring minimal UI/API only if needed for tests (otherwise defer)
MD

echo "Wrote docs/PHASE_2_BRIEF.md"
