# Architecture (Overview)

This project implements a compact, secure platform for workshop management with the following architectural characteristics:

- **Frontend:** Next.js application (App Router) delivering the admin UI and any public pages.
- **Backend / DB:** Postgres (server-side logic in SQL + migrations) accessed via `postgres` (postgres-js) and Drizzle for schema/migrations.
- **Tenancy & RLS:** Multi-tenant model (orgs → sites → memberships). Postgres Row-Level Security (RLS) enforces fail-closed access rules using request-scoped session variables (`app.user_id`, `app.org_id`).
- **Audit & Observability:** Append-only `audit_log` with materialised feed views (`v_audit_log_feed`) to support feed APIs and privacy-sensitive views.
- **Testing & CI:** Integration tests run against a real Postgres instance in CI; migrations are applied before tests.

Tips for contributors
- Keep migration-first mindset: change the schema via migrations, not by editing generated schema files in-place.
- Prefer explicit SQL for security-critical logic (RLS policies, definer functions), and add tests that exercise RLS conditions.
