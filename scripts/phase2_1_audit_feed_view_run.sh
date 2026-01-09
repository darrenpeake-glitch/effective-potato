#!/usr/bin/env bash
set -euo pipefail

# Better error output than "exit 3".
trap 'echo; echo "ERROR: command failed on line $LINENO"; echo "Last command: $BASH_COMMAND"; exit 3' ERR

echo "==> Phase 2.1: audit feed view + indexes (diagnose + run)"

if [[ ! -f ".env.test" ]]; then
  echo "ERROR: .env.test not found."
  echo "Create .env.test first, then re-run."
  exit 3
fi

# Robust .env loader (handles quoted values and CRLF)
load_env_var () {
  local key="$1"
  local raw
  raw="$(grep -E "^${key}=" .env.test | tail -n 1 || true)"
  if [[ -z "${raw}" ]]; then
    echo "ERROR: ${key} not found in .env.test"
    exit 3
  fi
  local val="${raw#*=}"
  # strip CR, surrounding quotes, and whitespace
  val="${val//$'\r'/}"
  val="${val#\"}"; val="${val%\"}"
  val="${val#\'}"; val="${val%\'}"
  val="$(echo -n "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [[ -z "${val}" ]]; then
    echo "ERROR: ${key} is empty in .env.test"
    exit 3
  fi
  printf -v "$key" '%s' "$val"
  export "$key"
}

load_env_var DATABASE_URL_MIGRATE
load_env_var DATABASE_URL_APP

echo "==> Sanity check URLs"
case "${DATABASE_URL_MIGRATE}" in
  postgresql://*|postgres://*) ;;
  *)
    echo "ERROR: DATABASE_URL_MIGRATE must be a full postgres URI (postgresql://...)"
    echo "Got: ${DATABASE_URL_MIGRATE}"
    exit 3
    ;;
esac

case "${DATABASE_URL_APP}" in
  postgresql://*|postgres://*) ;;
  *)
    echo "ERROR: DATABASE_URL_APP must be a full postgres URI (postgresql://...)"
    echo "Got: ${DATABASE_URL_APP}"
    exit 3
    ;;
esac

command -v psql >/dev/null 2>&1 || { echo "ERROR: psql not found in PATH."; exit 3; }

echo "==> Connectivity check (MIGRATE)"
psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=1 -c "select current_user, session_user;" >/dev/null

echo "==> Connectivity check (APP)"
psql "${DATABASE_URL_APP}" -v ON_ERROR_STOP=1 -c "select current_user, session_user;" >/dev/null

MIGR_DIR="src/db/migrations"
mkdir -p "${MIGR_DIR}"
STAMP="$(date +%Y%m%d_%H%M%S)"
MIGR_FILE="${MIGR_DIR}/${STAMP}_phase2_1_audit_feed_view.sql"

echo "==> Writing migration: ${MIGR_FILE}"
cat > "${MIGR_FILE}" <<'SQL'
-- Phase 2.1: Audit feed performance + read-only view
-- Idempotent.

BEGIN;

-- Indexes for feed queries
CREATE INDEX IF NOT EXISTS audit_log_org_created_at_id_desc_idx
  ON public.audit_log (org_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS audit_log_org_entity_entity_id_created_at_id_desc_idx
  ON public.audit_log (org_id, entity, entity_id, created_at DESC, id DESC);

-- Read-only feed view (RLS still enforced on underlying table)
CREATE OR REPLACE VIEW public.v_audit_log_feed AS
SELECT
  id,
  org_id,
  actor_user_id,
  action,
  entity,
  entity_id,
  created_at,
  meta
FROM public.audit_log
ORDER BY created_at DESC, id DESC;

-- Grant SELECT on the view to known app roles if present (ignore if absent)
DO $$
BEGIN
  BEGIN
    EXECUTE 'GRANT SELECT ON public.v_audit_log_feed TO occono_app';
  EXCEPTION WHEN undefined_object THEN
    NULL;
  END;

  BEGIN
    EXECUTE 'GRANT SELECT ON public.v_audit_log_feed TO app_user';
  EXCEPTION WHEN undefined_object THEN
    NULL;
  END;
END $$;

COMMIT;
SQL

echo "==> Applying migration via DATABASE_URL_MIGRATE"
psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=1 -f "${MIGR_FILE}"

echo "==> Verify view + indexes"
psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=1 <<'SQL'
\pset pager off
SELECT to_regclass('public.v_audit_log_feed') AS view_regclass;

SELECT indexname
FROM pg_indexes
WHERE schemaname='public'
  AND tablename='audit_log'
  AND indexname IN (
    'audit_log_org_created_at_id_desc_idx',
    'audit_log_org_entity_entity_id_created_at_id_desc_idx'
  )
ORDER BY indexname;
SQL

echo "==> Verify APP can SELECT the view (may return 0 rows under fail-closed RLS)"
psql "${DATABASE_URL_APP}" -v ON_ERROR_STOP=1 <<'SQL'
\pset pager off
SELECT current_user, session_user;
SELECT id, org_id, action, entity, created_at
FROM public.v_audit_log_feed
LIMIT 1;
SQL

echo "==> SUCCESS: Phase 2.1 audit feed view created/applied."
echo "==> Migration file: ${MIGR_FILE}"
