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

Development can safely proceed to Phase 2.
