# Build State

Last updated: 2026-01-09

This document reflects the current, verified build status of the system.
All statements below are backed by migrations, tests, and repeatable scripts.

---

## Phase 1 — Core Data + Security (COMPLETE)

**Status:** ✅ Complete  
**Confidence:** High (migrations + RLS + integration tests passing)

### Scope (Delivered)

#### Database Schema
- Core multi-tenant entities implemented:
  - `orgs`
  - `memberships`
  - `sites`
  - `audit_log`
- UUID primary keys everywhere
- Foreign keys enforced
- Deterministic IDs supported for tests
- Append-only audit log

#### Row-Level Security (Fail-Closed)
- RLS enabled on all tenant-scoped tables:
  - `orgs`
  - `memberships`
  - `sites`
  - `audit_log`
- Default posture is **deny all**
- Access only granted when:
  - `app.user_id` is set
  - `app.org_id` is set
  - user is a member of the org
- Cross-tenant reads and writes are blocked
- Invalid or missing context fails closed

#### Roles & Privileges
- **Admin role**
  - Owns schemas and tables
  - Runs migrations
  - Can bypass RLS when required
- **App role**
  - Cannot bypass RLS
  - Cannot write protected tables (`orgs`, `memberships`, `audit_log`)
  - Can only read/write via RLS-approved paths
- No ALTER TABLE permissions granted to app role
- Drizzle migration schema owned by migration/admin role

#### Application Context Model
- `app.user_id` and `app.org_id` set via session variables
- Centralized helpers enforce context in tests
- Invalid context is detectable and testable

#### Repository Layer
- Server-only write paths for:
  - org creation
  - membership management
  - audit logging
- App-side reads and writes strictly constrained by RLS
- Repo functions tested against real Postgres + RLS

#### Test Infrastructure
- Real database (Neon) used in tests
- Separate URLs for:
  - admin
  - app
  - migrate
- Deterministic setup via shell scripts
- Tests cover:
  - fail-closed behavior
  - tenant isolation
  - privilege enforcement
  - audit append-only guarantees

#### Tooling & Scripts
- Executable scripts (no copy/paste required):
  - environment setup
  - app role provisioning (no ALTER TABLE)
  - migrations
  - test execution
- `.env.test` is the single source of truth
- `drizzle-kit` wired explicitly to migration URL

---

## Phase 2 — Domain Expansion (NOT STARTED)

**Status:** ⏸ Not started  
**Blocked by:** nothing

### Planned Scope (Tentative)
- Additional domain entities
- Business-level invariants enforced via RLS + constraints
- Expanded audit coverage
- Read models / projections if required

No Phase 2 schema or logic has been implemented yet.

---

## Invariants (Must Not Break)

The following are **non-negotiable** going forward:

- No app-side bypass of RLS
- No implicit tenant access
- No shared tables without tenant scoping
- No migrations run under app credentials
- All security behavior must be test-proven

Any change that violates these requires explicit redesign and test updates.

---

## Summary

Phase 1 is complete, hardened, and reproducible.

The system now has:
- a secure multi-tenant core,
- deterministic tests,
- clear role separation,
- and a reliable migration pipeline.

## Phase 1 — Complete

Status: ✅ Complete

- Core schema finalised (orgs, sites, memberships, audit_log)
- Row Level Security enabled and forced on all tenant tables
- Fail-closed access model enforced
- Explicit app/server role separation
- audit_log hardened:
  - Append-only
  - Server-write-only
  - Tenant-scoped reads
- Integration tests passing against real Postgres
- Repeatable test + migration environment established

## Phase 2 — Ready

Entry conditions met:
- No schema churn expected in Phase 2
- RLS policies stable and verified
- Safe domain expansion possible without weakening isolation
Development can safely proceed to Phase 2.

---

## Phase 2 — Audit Read Surface (In Progress)

### Goal
Deliver a **read-only Activity Feed** backed by `public.audit_log` with **no additional write power** granted to the app role.

### Non-negotiable constraints
- **No relaxation of RLS**; continue fail-closed semantics.
- App role remains **SELECT-only** on `audit_log` (and feed views).
- `audit_log` remains **server-only writable** (migrate/service roles only).
- No new tenant-scoped write tables in Phase 2 unless explicitly required.

### Scope (Deliverables)
1. **DB read model**
   - `public.v_audit_log_feed` view (projection over `public.audit_log`, RLS applies at base table)
   - Indexes to support pagination and filtering:
     - `(org_id, created_at desc, id desc)`
     - `(org_id, entity, entity_id, created_at desc, id desc)`
     - optional `(org_id, action, created_at desc)`

2. **Repo layer**
   - `listAuditFeed({ limit, cursor })`
   - `listEntityAudit({ entity, entityId, limit, cursor })`
   - Deterministic ordering: `ORDER BY created_at DESC, id DESC`

3. **Tests**
   - Existing Phase-1 tests continue to pass.
   - Add coverage for:
     - feed ordering stability
     - cursor pagination correctness
     - entity filtering correctness
     - non-member sees empty (or error if invalid context guards apply)

### Definition of Done
- `pnpm test` passes
- `pnpm typecheck` passes
- Feed queries return correct results under RLS
- No new privileges granted to the app role beyond read access for the feed view
