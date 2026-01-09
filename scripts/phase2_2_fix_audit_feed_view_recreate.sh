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
MIGR_FILE="${MIGR_DIR}/0013_phase2_2_recreate_audit_feed_view.sql"

mkdir -p "$MIGR_DIR"

echo "==> Writing migration: $MIGR_FILE"
cat > "$MIGR_FILE" <<SQL
-- 0013_phase2_2_recreate_audit_feed_view.sql
-- Fix: Drop and recreate audit_feed to avoid CREATE OR REPLACE column-mapping conflicts.

BEGIN;

-- Drop first so Postgres does not attempt to remap existing column names/order.
DROP VIEW IF EXISTS public.audit_feed;

-- Recreate as SECURITY INVOKER so RLS applies to the caller (app_user), not the owner.
CREATE VIEW public.audit_feed
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

echo "==> Done. Now re-run tests:"
echo "pnpm test"
