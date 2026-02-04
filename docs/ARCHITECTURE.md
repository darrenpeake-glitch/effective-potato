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

Local development notes 🛠️
- Some migrations grant privileges to a role named `occono_app`. Migrations are idempotent and will skip the grant when the role is absent, but if you want to test RLS behavior against a non-superuser local app connection, create a login role locally (example below):

  ```bash
  # Create a login role with password (for local testing only; pick a secure password)
  docker exec -it <postgres-container> psql -U postgres -c "CREATE ROLE occono_app WITH LOGIN PASSWORD 'occono_pass';"

  # Then run tests with DATABASE_URL_APP pointing at occono_app
  export DATABASE_URL_APP="postgresql://occono_app:occono_pass@localhost:5432/postgres?sslmode=disable"
  pnpm db:migrate && pnpm test
  ```

- CI does not require the login role; migrations will create a NOLOGIN `occono_app` role to satisfy grant statements.
