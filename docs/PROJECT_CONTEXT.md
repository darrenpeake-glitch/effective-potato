# Occono Auto Rebuild — Project Context (Canonical)

## Purpose
Engineering-first rebuild of Occono Auto with a focus on correctness, security, and long-term maintainability. Feature velocity is explicitly deprioritised until platform foundations are proven.

## Stack (Authoritative)
- App: Next.js (App Router) + TypeScript
- Runtime: Node.js (Vercel-compatible)
- Database: Neon Postgres
- ORM & Migrations: Drizzle ORM + drizzle-kit
- Auth: Auth.js (NextAuth)
- Testing: Vitest (unit + integration), Playwright (smoke)
- CI: GitHub Actions

## Core Principles (Non-Negotiable)
1. Multi-tenant by default (org/site scoping everywhere).
2. Postgres-enforced Row Level Security (fail-closed).
3. Runtime DB role cannot bypass RLS.
4. All DB access flows through a single request-scoped DB context.
5. No feature development before tests + CI gates exist.

## Tenancy Model
- orgs: top-level tenant
- sites: belong to orgs
- memberships: user ↔ org with role

## Explicit Non-Goals (Phase 1)
- Public marketing pages
- Billing / Stripe
- Messaging / integrations
- Workshop domain features (jobs, vehicles, invoicing)
