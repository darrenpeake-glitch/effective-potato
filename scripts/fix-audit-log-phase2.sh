#!/usr/bin/env bash
set -euo pipefail

APP_ROLE_NAME="${APP_ROLE_NAME:-app_user}"
LEGACY_APP_ROLE_NAME="${LEGACY_APP_ROLE_NAME:-occono_app}"
SERVER_ROLES_CSV="${SERVER_ROLES_CSV:-occono_migrate,neondb_owner}"

if [[ ! -f ".env.test" ]]; then
  echo "ERROR: .env.test not found."
  exit 1
fi

set -a
source .env.test
set +a

: "${DATABASE_URL_MIGRATE:?ERROR: DATABASE_URL_MIGRATE missing in .env.test (must be a full postgres URL)}"

if [[ "${DATABASE_URL_MIGRATE}" != postgresql://* && "${DATABASE_URL_MIGRATE}" != postgres://* ]]; then
  echo "ERROR: DATABASE_URL_MIGRATE must be a full postgres URL (postgresql://...)."
  echo "Got: ${DATABASE_URL_MIGRATE}"
  exit 1
fi

command -v psql >/dev/null 2>&1 || { echo "ERROR: psql not found on PATH."; exit 1; }

echo "==> Fixing audit_log for Phase 2"
echo "==> Using DATABASE_URL_MIGRATE host: $(python - <<'PY'
import os, urllib.parse
u=urllib.parse.urlparse(os.environ["DATABASE_URL_MIGRATE"])
print(u.hostname or "")
PY
)"
echo "==> APP role: ${APP_ROLE_NAME}"
echo "==> Legacy app role (optional): ${LEGACY_APP_ROLE_NAME}"
echo "==> Server roles: ${SERVER_ROLES_CSV}"

# Build server roles SQL array literal: ARRAY['a','b',...]
IFS=',' read -r -a SERVER_ROLES <<< "${SERVER_ROLES_CSV}"
SERVER_ROLES_SQL=""
for r in "${SERVER_ROLES[@]}"; do
  rr="$(echo "$r" | xargs)"
  [[ -z "$rr" ]] && continue
  if [[ -n "${SERVER_ROLES_SQL}" ]]; then SERVER_ROLES_SQL="${SERVER_ROLES_SQL},"; fi
  SERVER_ROLES_SQL="${SERVER_ROLES_SQL}'${rr}'"
done
if [[ -z "${SERVER_ROLES_SQL}" ]]; then
  echo "ERROR: SERVER_ROLES_CSV resolved to empty."
  exit 1
fi

# Use a bash array so quoting is real (no literal quotes passed to psql)
PSQL=(psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=1 -X -q)

"${PSQL[@]}" <<SQL
BEGIN;

-- Hard enforce RLS (Phase 2 expects FORCE RLS on audit_log)
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log FORCE ROW LEVEL SECURITY;

-- Drop all existing policies on audit_log (correct column name: policyname)
DO \$\$
DECLARE
  pol record;
BEGIN
  FOR pol IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'audit_log'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.audit_log;', pol.policyname);
  END LOOP;
END
\$\$;

-- Fail-closed privileges
REVOKE ALL ON public.audit_log FROM PUBLIC;

-- App roles: read-only
REVOKE INSERT, UPDATE, DELETE ON public.audit_log FROM "${APP_ROLE_NAME}";
GRANT  SELECT                 ON public.audit_log TO   "${APP_ROLE_NAME}";

DO \$\$
BEGIN
  IF '${LEGACY_APP_ROLE_NAME}' <> '' THEN
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE ON public.audit_log FROM %I;', '${LEGACY_APP_ROLE_NAME}');
    EXECUTE format('GRANT  SELECT                 ON public.audit_log TO   %I;', '${LEGACY_APP_ROLE_NAME}');
  END IF;
END
\$\$;

-- Server roles: full access
DO \$\$
DECLARE
  r text;
BEGIN
  FOREACH r IN ARRAY ARRAY[${SERVER_ROLES_SQL}] LOOP
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.audit_log TO %I;', r);
  END LOOP;
END
\$\$;

-- RLS policies:
-- SELECT: only in-org, only with valid context + membership
CREATE POLICY audit_log_select
ON public.audit_log
FOR SELECT
USING (
  public.has_app_context()
  AND public.require_valid_user()
  AND public.require_valid_org()
  AND org_id = public.app_org_id()
  AND public.is_org_member(org_id)
);

-- Explicit deny writes (defense-in-depth)
CREATE POLICY audit_log_insert_deny
ON public.audit_log
FOR INSERT
WITH CHECK (false);

CREATE POLICY audit_log_update_deny
ON public.audit_log
FOR UPDATE
USING (false)
WITH CHECK (false);

CREATE POLICY audit_log_delete_deny
ON public.audit_log
FOR DELETE
USING (false);

COMMIT;
SQL

echo "==> Verifying audit_log policies + grants (summary)"
"${PSQL[@]}" <<'SQL'
\pset pager off

SELECT schemaname, tablename, policyname, roles, cmd, permissive
FROM pg_policies
WHERE schemaname='public' AND tablename='audit_log'
ORDER BY policyname;

SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema='public' AND table_name='audit_log'
ORDER BY grantee, privilege_type;

SELECT c.relrowsecurity, c.relforcerowsecurity
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relname='audit_log';
SQL

echo "==> Done: audit_log Phase-2 hardening applied."
