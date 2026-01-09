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

MIGR_DIR="src/db/migrations"
MIGR_FILE="${MIGR_DIR}/0015_phase2_2_fix_app_privs_all.sql"
mkdir -p "$MIGR_DIR"

# Roles we want to support. app_user is canonical; occono_app is legacy/optional.
APP_ROLE_1="${APP_ROLE_NAME:-app_user}"
APP_ROLE_2="${LEGACY_APP_ROLE_NAME:-occono_app}"

echo "==> Writing migration: $MIGR_FILE"
cat > "$MIGR_FILE" <<SQL
-- 0015_phase2_2_fix_app_privs_all.sql
-- Purpose:
--   Ensure the role used by the application/tests has BASE privileges.
--   RLS remains the tenant boundary; these are required for queries to run at all.
--
-- Strategy:
--   - Apply grants to app_user and (if it exists) occono_app.
--   - Grant across ALL TABLES / ALL FUNCTIONS in public schema to avoid missing objects/signatures.
--   - Add default privileges so future objects don't regress.

BEGIN;

DO \$\$
DECLARE
  r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['${APP_ROLE_1}', '${APP_ROLE_2}']
  LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      -- Schema access
      EXECUTE format('GRANT USAGE ON SCHEMA public TO %I;', r);

      -- Tables: allow the app role to run SELECT/INSERT/UPDATE/DELETE, with RLS enforcing tenant rules.
      EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO %I;', r);

      -- Sequences (needed if any table uses serial/identity + nextval)
      EXECUTE format('GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO %I;', r);

      -- Functions: policies/guards often call helper functions; grant EXECUTE broadly.
      EXECUTE format('GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO %I;', r);

      -- Default privileges for future objects created in public schema.
      -- Note: these apply to objects created by the current owner role executing this migration.
      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I;', r);
      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO %I;', r);
      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO %I;', r);
    END IF;
  END LOOP;
END
\$\$;

COMMIT;
SQL

echo "==> Applying migration via DATABASE_URL_MIGRATE"
psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=1 -f "${MIGR_FILE}"

echo "==> Done. Now re-run tests:"
echo "pnpm test"
