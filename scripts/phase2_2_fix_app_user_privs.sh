#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 3; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

require_cmd psql

[[ -f .env.test ]] || die ".env.test not found"
set -a
source .env.test
set +a

: "${DATABASE_URL_MIGRATE:?DATABASE_URL_MIGRATE missing in .env.test}"

APP_ROLE_NAME="${APP_ROLE_NAME:-app_user}"

MIGR_DIR="src/db/migrations"
MIGR_FILE="${MIGR_DIR}/0014_phase2_2_fix_app_user_privs.sql"

mkdir -p "$MIGR_DIR"

echo "==> Writing migration: $MIGR_FILE"
cat > "$MIGR_FILE" <<SQL
-- 0014_phase2_2_fix_app_user_privs.sql
-- Purpose: ensure app role has base privileges required for RLS + guard functions to work.
-- RLS remains the actual tenant/security boundary; these GRANTs are required plumbing.

BEGIN;

-- Schema usage
GRANT USAGE ON SCHEMA public TO "${APP_ROLE_NAME}";

-- Table privileges (minimum required by tests and repos)
GRANT SELECT ON public.orgs        TO "${APP_ROLE_NAME}";
GRANT SELECT ON public.memberships TO "${APP_ROLE_NAME}";
GRANT SELECT ON public.audit_log   TO "${APP_ROLE_NAME}";
GRANT SELECT ON public.users       TO "${APP_ROLE_NAME}";

-- Sites are APP-writable under RLS policies
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sites TO "${APP_ROLE_NAME}";

-- View privilege (in case earlier migration ran before role grants)
GRANT SELECT ON public.audit_feed TO "${APP_ROLE_NAME}";

-- Helper function EXECUTE privileges (policies/guards call these)
GRANT EXECUTE ON FUNCTION public.app_user_id() TO "${APP_ROLE_NAME}";
GRANT EXECUTE ON FUNCTION public.app_org_id()  TO "${APP_ROLE_NAME}";
GRANT EXECUTE ON FUNCTION public.is_org_member(uuid) TO "${APP_ROLE_NAME}";

-- These exist in your later migrations (gate + require_valid_*). Grant if present.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='has_app_context'
  ) THEN
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.has_app_context() TO %I;', '${APP_ROLE_NAME}');
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='require_valid_user'
  ) THEN
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.require_valid_user() TO %I;', '${APP_ROLE_NAME}');
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='require_valid_org'
  ) THEN
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.require_valid_org() TO %I;', '${APP_ROLE_NAME}');
  END IF;
END $$;

COMMIT;
SQL

echo "==> Applying migration via DATABASE_URL_MIGRATE"
psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=1 -f "${MIGR_FILE}"

echo "==> Done. Re-run tests:"
echo "pnpm test"
