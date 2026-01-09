#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Config
# -----------------------------
MIGR_DIR="src/db/migrations"
MIGR_FILE="${MIGR_DIR}/phase2_1_audit_feed_view.sql"

# -----------------------------
# Helpers
# -----------------------------
die() { echo "ERROR: $*" >&2; exit 3; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

is_pg_url() {
  local v="${1:-}"
  [[ "$v" == postgres://* || "$v" == postgresql://* ]]
}

# -----------------------------
# Preflight
# -----------------------------
require_cmd psql

[[ -f ".env.test" ]] || die ".env.test not found at repo root."
set -a
# shellcheck disable=SC1091
source .env.test
set +a

: "${DATABASE_URL_MIGRATE:?DATABASE_URL_MIGRATE is missing in .env.test}"

# Defensive trim: sometimes people accidentally paste leading/trailing quotes/spaces.
DATABASE_URL_MIGRATE="${DATABASE_URL_MIGRATE%\"}"
DATABASE_URL_MIGRATE="${DATABASE_URL_MIGRATE#\"}"
DATABASE_URL_MIGRATE="$(echo -n "$DATABASE_URL_MIGRATE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

is_pg_url "$DATABASE_URL_MIGRATE" || die "DATABASE_URL_MIGRATE must start with postgres:// or postgresql:// (got: ${DATABASE_URL_MIGRATE:0:24}...)"

mkdir -p "$MIGR_DIR"

# -----------------------------
# Write migration (idempotent)
# -----------------------------
cat > "$MIGR_FILE" <<'SQL'
BEGIN--
-- Phase 2.1: Audit feed view
-- Purpose:
--   Provide a stable, query-friendly "feed" projection over audit_log with actor details.
-- Safety:
--   - View is SECURITY INVOKER (default): RLS on audit_log still applies for app roles.
--   - No writes; app should be granted SELECT only.
--

BEGIN;

-- Keep it idempotent.
CREATE OR REPLACE VIEW public.audit_feed AS
SELECT
  al.id,
  al.org_id,
  al.created_at,
  al.action,
  al.entity,
  al.entity_id,
  al.meta,
  al.actor_user_id,
  u.email      AS actor_email,
  u.name       AS actor_name
FROM public.audit_log al
LEFT JOIN public.users u
  ON u.id = al.actor_user_id;

COMMENT ON VIEW public.audit_feed IS
'Phase 2.1 audit feed projection (audit_log + users). SECURITY INVOKER; audit_log RLS governs visibility.';

-- Privileges: allow app read-only access (do not assume a specific app role name exists).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
    GRANT SELECT ON public.audit_feed TO app_user;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'occono_app') THEN
    GRANT SELECT ON public.audit_feed TO occono_app;
  END IF;

  -- Migrate/admin roles commonly used in your environment
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'occono_migrate') THEN
    GRANT SELECT ON public.audit_feed TO occono_migrate;
  END IF;
END$$;

COMMIT;
SQL

echo "==> Wrote migration: ${MIGR_FILE}"

# -----------------------------
# Apply migration with visible errors
# -----------------------------
echo "==> Applying migration via DATABASE_URL_MIGRATE (psql)"
echo "==> Host preview: $(echo "$DATABASE_URL_MIGRATE" | sed -E 's#(postgres(ql)?://)([^@]+@)?([^/:?]+).*#\4#')"

# Always show the underlying error if psql fails.
# Use env var for connection string to avoid any edge-case parsing of positional args.
export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"
export DATABASE_URL_MIGRATE

set +e
PSQL_ERR="$(mktemp)"
psql "$DATABASE_URL_MIGRATE" -v ON_ERROR_STOP=1 -f "$MIGR_FILE" 2>"$PSQL_ERR"
PSQL_RC=$?
set -e

if [[ $PSQL_RC -ne 0 ]]; then
  echo "==> psql failed (exit $PSQL_RC). Error output:" >&2
  sed -n '1,200p' "$PSQL_ERR" >&2
  rm -f "$PSQL_ERR"
  exit 3
fi

rm -f "$PSQL_ERR"

# -----------------------------
# Verify
# -----------------------------
echo "==> Verifying view exists"
psql "$DATABASE_URL_MIGRATE" -v ON_ERROR_STOP=1 -c "select to_regclass('public.audit_feed') as audit_feed_regclass;"

echo "==> Done: Phase 2.1 audit_feed view created/updated successfully."
