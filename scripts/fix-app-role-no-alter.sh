#!/usr/bin/env bash
set -euo pipefail

APP_ROLE_NAME="${APP_ROLE_NAME:-app_user}"
APP_ROLE_PASSWORD="${APP_ROLE_PASSWORD:-app_user_dev_pw_change_me}"

if [[ ! -f ".env.test" ]]; then
  echo "ERROR: .env.test not found."
  exit 1
fi

set -a
source .env.test
set +a

: "${DATABASE_URL_ADMIN:?ERROR: DATABASE_URL_ADMIN missing in .env.test}"

if [[ "${DATABASE_URL_ADMIN}" != postgresql://* && "${DATABASE_URL_ADMIN}" != postgres://* ]]; then
  echo "ERROR: DATABASE_URL_ADMIN must be a full postgres URL (postgresql://...)."
  echo "Got: ${DATABASE_URL_ADMIN}"
  exit 1
fi

command -v psql >/dev/null 2>&1 || { echo "ERROR: psql not found."; exit 1; }
command -v perl >/dev/null 2>&1 || { echo "ERROR: perl not found."; exit 1; }

ADMIN_USER="$(python3 - <<'PY'
import os, urllib.parse
u = urllib.parse.urlparse(os.environ["DATABASE_URL_ADMIN"])
print(u.username or "")
PY
)"
ADMIN_HOSTPORT="$(python3 - <<'PY'
import os, urllib.parse
u = urllib.parse.urlparse(os.environ["DATABASE_URL_ADMIN"])
hp = u.hostname or ""
if u.port:
  hp += f":{u.port}"
print(hp)
PY
)"
ADMIN_DBNAME="$(python3 - <<'PY'
import os, urllib.parse
u = urllib.parse.urlparse(os.environ["DATABASE_URL_ADMIN"])
print((u.path or "").lstrip("/"))
PY
)"
ADMIN_QUERY="$(python3 - <<'PY'
import os, urllib.parse
u = urllib.parse.urlparse(os.environ["DATABASE_URL_ADMIN"])
print(("?"+u.query) if u.query else "")
PY
)"

if [[ -z "$ADMIN_USER" || -z "$ADMIN_HOSTPORT" || -z "$ADMIN_DBNAME" ]]; then
  echo "ERROR: Could not parse DATABASE_URL_ADMIN."
  exit 1
fi

APP_URL="postgresql://${APP_ROLE_NAME}:${APP_ROLE_PASSWORD}@${ADMIN_HOSTPORT}/${ADMIN_DBNAME}${ADMIN_QUERY}"
export APP_URL

echo "==> Admin user: ${ADMIN_USER}"
echo "==> Target app role: ${APP_ROLE_NAME}"
echo "==> Target db: ${ADMIN_DBNAME} @ ${ADMIN_HOSTPORT}"

echo "==> Writing corrected DATABASE_URL_APP and DATABASE_URL_MIGRATE into .env.test"
perl -0777 -i -pe '
  my $app = $ENV{APP_URL} // "";
  my $admin = $ENV{DATABASE_URL_ADMIN} // "";
  s/^DATABASE_URL_APP=.*\n//m;
  s/^DATABASE_URL_MIGRATE=.*\n//m;
  $_ .= "DATABASE_URL_APP=\"$app\"\n";
  $_ .= "DATABASE_URL_MIGRATE=\"$admin\"\n";
' .env.test

set -a
source .env.test
set +a

if [[ -z "${DATABASE_URL_APP:-}" ]]; then
  echo "ERROR: DATABASE_URL_APP is empty after updating .env.test"
  echo "Check .env.test contents:"
  sed -n '1,200p' .env.test
  exit 1
fi

echo "==> Sanity check .env.test now contains:"
grep -E '^DATABASE_URL_(ADMIN|APP|MIGRATE)=' .env.test || true

echo "==> Creating/resetting APP role + privileges (no ALTER TABLE)"
psql "${DATABASE_URL_ADMIN}" -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${APP_ROLE_NAME}') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '${APP_ROLE_NAME}', '${APP_ROLE_PASSWORD}');
  ELSE
    EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', '${APP_ROLE_NAME}', '${APP_ROLE_PASSWORD}');
  END IF;
END
\$\$;

ALTER ROLE "${APP_ROLE_NAME}" NOBYPASSRLS;

GRANT CONNECT ON DATABASE "${ADMIN_DBNAME}" TO "${APP_ROLE_NAME}";

REVOKE ALL ON SCHEMA public FROM "${APP_ROLE_NAME}";
GRANT USAGE ON SCHEMA public TO "${APP_ROLE_NAME}";

REVOKE ALL ON TABLE public.orgs FROM "${APP_ROLE_NAME}";
GRANT SELECT ON TABLE public.orgs TO "${APP_ROLE_NAME}";

REVOKE ALL ON TABLE public.memberships FROM "${APP_ROLE_NAME}";
GRANT SELECT ON TABLE public.memberships TO "${APP_ROLE_NAME}";

REVOKE ALL ON TABLE public.sites FROM "${APP_ROLE_NAME}";
GRANT SELECT, INSERT ON TABLE public.sites TO "${APP_ROLE_NAME}";

REVOKE ALL ON TABLE public.audit_log FROM "${APP_ROLE_NAME}";
GRANT SELECT ON TABLE public.audit_log TO "${APP_ROLE_NAME}";

SELECT rolname, rolbypassrls FROM pg_roles WHERE rolname = '${APP_ROLE_NAME}';
SQL

echo "==> Verifying APP connection identity (must not default to local socket)"
psql "${DATABASE_URL_APP}" -v ON_ERROR_STOP=1 <<'SQL'
SELECT current_user, session_user;
SELECT rolname, rolbypassrls FROM pg_roles WHERE rolname = current_user;
SQL

echo "==> Showing RLS flags + owners (read-only)"
psql "${DATABASE_URL_ADMIN}" -v ON_ERROR_STOP=1 <<'SQL'
SELECT c.relname, n.nspname, r.rolname AS owner, c.relrowsecurity, c.relforcerowsecurity
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_roles r ON r.oid = c.relowner
WHERE n.nspname='public' AND c.relname IN ('orgs','memberships','sites','audit_log')
ORDER BY c.relname;
SQL

echo "==> Running migrations via DATABASE_URL_MIGRATE (ADMIN)"
pnpm -s db:migrate

echo "==> Running tests"
pnpm -s test

echo "==> DONE"
