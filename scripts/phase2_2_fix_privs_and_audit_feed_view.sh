#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 3; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

require_cmd psql
require_cmd pnpm

[[ -f .env.test ]] || die ".env.test not found"
set -a
source .env.test
set +a

: "${DATABASE_URL_MIGRATE:?DATABASE_URL_MIGRATE missing in .env.test}"

# Allow override, but default to your current app role name.
APP_ROLE_NAME="${APP_ROLE_NAME:-app_user}"

MIGR_DIR="src/db/migrations"
MIGR_FILE="${MIGR_DIR}/0012_phase2_2_app_privs_and_audit_feed_view.sql"

mkdir -p "$MIGR_DIR"

echo "==> Writing migration: $MIGR_FILE"
cat > "$MIGR_FILE" <<SQL
-- 0012_phase2_2_app_privs_and_audit_feed_view.sql
-- Purpose:
--   1) Ensure the *actual* app role used in tests (app_user) has required privileges.
--   2) Ensure audit_feed does not bypass RLS by running as view owner.
--
-- Assumptions:
--   - Core tables exist: public.orgs, public.sites, public.memberships, public.audit_log, public.users
--   - RLS helper functions exist in public: app_user_id(), app_org_id(), is_org_member(uuid),
--     has_app_context(), require_valid_user(), require_valid_org()
--   - Postgres version supports SECURITY INVOKER views (PG15+; Neon typically does)

BEGIN;

-- -----------------------------
-- 1) App role privileges
-- -----------------------------
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${APP_ROLE_NAME}') THEN
    RAISE EXCEPTION 'app role "%" does not exist', '${APP_ROLE_NAME}';
  END IF;
END
\$\$;

-- Schema usage
GRANT USAGE ON SCHEMA public TO "${APP_ROLE_NAME}";

-- Table privileges (RLS still applies)
-- Orgs: read-only
GRANT SELECT ON public.orgs TO "${APP_ROLE_NAME}";
REVOKE INSERT, UPDATE, DELETE ON public.orgs FROM "${APP_ROLE_NAME}";

-- Memberships: read-only (per policy)
GRANT SELECT ON public.memberships TO "${APP_ROLE_NAME}";
REVOKE INSERT, UPDATE, DELETE ON public.memberships FROM "${APP_ROLE_NAME}";

-- Sites: read/write under RLS policies
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sites TO "${APP_ROLE_NAME}";

-- Audit_log: SELECT only (append-only server writes)
GRANT SELECT ON public.audit_log TO "${APP_ROLE_NAME}";
REVOKE INSERT, UPDATE, DELETE ON public.audit_log FROM "${APP_ROLE_NAME}";

-- Users: read-only (used for joining actor info in views)
GRANT SELECT ON public.users TO "${APP_ROLE_NAME}";

-- Function EXECUTE privileges (RLS policies call these)
GRANT EXECUTE ON FUNCTION public.app_user_id() TO "${APP_ROLE_NAME}";
GRANT EXECUTE ON FUNCTION public.app_org_id() TO "${APP_ROLE_NAME}";
GRANT EXECUTE ON FUNCTION public.is_org_member(uuid) TO "${APP_ROLE_NAME}";

-- These exist in your current policy set (seen in output)
GRANT EXECUTE ON FUNCTION public.has_app_context() TO "${APP_ROLE_NAME}";
GRANT EXECUTE ON FUNCTION public.require_valid_user() TO "${APP_ROLE_NAME}";
GRANT EXECUTE ON FUNCTION public.require_valid_org() TO "${APP_ROLE_NAME}";

-- Older/alternate guard function names may exist in repo history; grant if present.
DO \$\$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
             WHERE n.nspname='public' AND p.proname='assert_valid_user') THEN
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.assert_valid_user() TO %I', '${APP_ROLE_NAME}');
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
             WHERE n.nspname='public' AND p.proname='assert_valid_org') THEN
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.assert_valid_org() TO %I', '${APP_ROLE_NAME}');
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
             WHERE n.nspname='public' AND p.proname='require_valid_user') THEN
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.require_valid_user() TO %I', '${APP_ROLE_NAME}');
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
             WHERE n.nspname='public' AND p.proname='require_valid_org') THEN
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.require_valid_org() TO %I', '${APP_ROLE_NAME}');
  END IF;
END
\$\$;

-- -----------------------------
-- 2) Recreate audit_feed as SECURITY INVOKER (prevents RLS bypass)
-- -----------------------------
-- Notes:
-- - Without SECURITY INVOKER, a view typically runs with view-owner privileges, which can bypass RLS.
-- - We return meta as jsonb (not text) to keep it structured.
CREATE OR REPLACE VIEW public.audit_feed
WITH (security_invoker = true)
AS
SELECT
  a.id,
  a.org_id,
  a.actor_user_id,
  u.name  AS actor_name,
  u.email AS actor_email,
  a.action,
  a.entity,
  a.entity_id,
  a.meta,
  a.created_at
FROM public.audit_log a
LEFT JOIN public.users u ON u.id = a.actor_user_id;

GRANT SELECT ON public.audit_feed TO "${APP_ROLE_NAME}";

COMMIT;
SQL

echo "==> Applying migration via DATABASE_URL_MIGRATE"
psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=1 -f "${MIGR_FILE}"

echo "==> Sanity: show privileges for app role (orgs/sites/audit_feed)"
psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=1 <<SQL
\\pset pager off
SELECT 'orgs' AS obj, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema='public' AND table_name='orgs' AND grantee='${APP_ROLE_NAME}'
UNION ALL
SELECT 'sites' AS obj, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema='public' AND table_name='sites' AND grantee='${APP_ROLE_NAME}'
UNION ALL
SELECT 'audit_feed' AS obj, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema='public' AND table_name='audit_feed' AND grantee='${APP_ROLE_NAME}'
ORDER BY obj, privilege_type;
SQL

echo "==> Running tests"
pnpm test

echo "==> Phase 2.2 privileges + audit_feed SECURITY INVOKER applied successfully."
