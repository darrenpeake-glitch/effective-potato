#!/usr/bin/env bash
set -euo pipefail

MIGR_DIR="src/db/migrations"
MIGR_FILE="${MIGR_DIR}/phase2_1_audit_feed_view.sql"

die() { echo "ERROR: $*" >&2; exit 3; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

require_cmd psql
mkdir -p "$MIGR_DIR"

[[ -f ".env.test" ]] || die ".env.test not found at repo root."

set -a
# shellcheck disable=SC1091
source .env.test
set +a

: "${DATABASE_URL_MIGRATE:?DATABASE_URL_MIGRATE is missing in .env.test}"

# Trim accidental quotes/spaces
DATABASE_URL_MIGRATE="${DATABASE_URL_MIGRATE%\"}"
DATABASE_URL_MIGRATE="${DATABASE_URL_MIGRATE#\"}"
DATABASE_URL_MIGRATE="$(echo -n "$DATABASE_URL_MIGRATE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

if [[ "$DATABASE_URL_MIGRATE" != postgres://* && "$DATABASE_URL_MIGRATE" != postgresql://* ]]; then
  die "DATABASE_URL_MIGRATE must start with postgres:// or postgresql://"
fi

cat > "$MIGR_FILE" <<'SQL'
-- Phase 2.1: Audit feed view
-- Purpose:
--   Stable, query-friendly "feed" projection over audit_log with actor details.
-- Safety:
--   - VIEW is SECURITY INVOKER (default): audit_log RLS continues to govern visibility.
--   - Read-only surface; app gets SELECT only.

BEGIN;

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
  u.email AS actor_email,
  u.name  AS actor_name
FROM public.audit_log al
LEFT JOIN public.users u
  ON u.id = al.actor_user_id;

COMMENT ON VIEW public.audit_feed IS
'Phase 2.1 audit feed projection (audit_log + users). SECURITY INVOKER; audit_log RLS governs visibility.';

DO $$
BEGIN
  -- Grant SELECT to whichever app role exists in this environment.
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
    GRANT SELECT ON public.audit_feed TO app_user;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'occono_app') THEN
    GRANT SELECT ON public.audit_feed TO occono_app;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'occono_migrate') THEN
    GRANT SELECT ON public.audit_feed TO occono_migrate;
  END IF;
END$$;

COMMIT;
SQL

echo "==> Rewrote migration: $MIGR_FILE"
echo "==> Applying migration via DATABASE_URL_MIGRATE"

set +e
ERR="$(mktemp)"
psql "$DATABASE_URL_MIGRATE" -v ON_ERROR_STOP=1 -f "$MIGR_FILE" 2>"$ERR"
RC=$?
set -e

if [[ $RC -ne 0 ]]; then
  echo "==> psql failed (exit $RC). Error output:" >&2
  sed -n '1,200p' "$ERR" >&2
  rm -f "$ERR"
  exit 3
fi

rm -f "$ERR"

echo "==> Verifying view exists"
psql "$DATABASE_URL_MIGRATE" -v ON_ERROR_STOP=1 -c "select to_regclass('public.audit_feed') as audit_feed_regclass;"

echo "==> Done: audit_feed view is in place."
