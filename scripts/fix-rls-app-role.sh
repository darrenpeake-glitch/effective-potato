#!/usr/bin/env bash
set -euo pipefail

# ---------- config you can override ----------
APP_ROLE_NAME="${APP_ROLE_NAME:-app_user}"
APP_ROLE_PASSWORD="${APP_ROLE_PASSWORD:-app_user_dev_pw_change_me}"
# --------------------------------------------

if [[ ! -f ".env.test" ]]; then
  echo "ERROR: .env.test not found."
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env.test
set +a

: "${DATABASE_URL_ADMIN:?ERROR: DATABASE_URL_ADMIN missing in .env.test}"

if [[ "${DATABASE_URL_ADMIN}" != postgresql://* && "${DATABASE_URL_ADMIN}" != postgres://* ]]; then
  echo "ERROR: DATABASE_URL_ADMIN must be a full postgres URL (postgresql://...)."
  echo "Got: ${DATABASE_URL_ADMIN}"
  exit 1
fi

# Parse parts from DATABASE_URL_ADMIN: user, host, dbname, query
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
p = (u.path or "").lstrip("/")
print(p)
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

# Construct an app URL using the same host/db/query but with dedicated app role.
APP_URL="postgresql://${APP_ROLE_NAME}:${APP_ROLE_PASSWORD}@${ADMIN_HOSTPORT}/${ADMIN_DBNAME}${ADMIN_QUERY}"

echo "==> Admin user: ${ADMIN_USER}"
echo "==> Target app role: ${APP_ROLE_NAME}"
echo "==> Target db: ${ADMIN_DBNAME} @ ${ADMIN_HOSTPORT}"

echo "==> Ensuring psql is available"
command -v psql >/dev/null 2>&1 || { echo "ERROR: psql not found in this environment."; exit 1; }

echo "==> Creating/resetting APP role and privileges using ADMIN connection"
psql "${DATABASE_URL_ADMIN}" -v ON_ERROR_STOP=1 <<SQL
-- 1) Create app role (or reset password if it already exists)
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${APP_ROLE_NAME}') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '${APP_ROLE_NAME}', '${APP_ROLE_PASSWORD}');
  ELSE
    EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', '${APP_ROLE_NAME}', '${APP_ROLE_PASSWORD}');
  END IF;
END
\$\$;

-- 2) Make sure app role does NOT bypass RLS
ALTER ROLE "${APP_ROLE_NAME}" NOBYPASSRLS;

-- 3) Allow connection + schema usage
GRANT CONNECT ON DATABASE "${ADMIN_DBNAME}" TO "${APP_ROLE_NAME}";
GRANT USAGE ON SCHEMA public TO "${APP_ROLE_NAME}";

-- 4) Revoke broad/default privileges (keep tight)
REVOKE ALL ON SCHEMA public FROM "${APP_ROLE_NAME}";
GRANT USAGE ON SCHEMA public TO "${APP_ROLE_NAME}";

-- 5) Table privileges (match intent of your tests)
-- ORGS: APP should be read-only under RLS
REVOKE ALL ON TABLE public.orgs FROM "${APP_ROLE_NAME}";
GRANT SELECT ON TABLE public.orgs TO "${APP_ROLE_NAME}";

-- MEMBERSHIPS: APP should be read-only (membership rows created by server/admin)
REVOKE ALL ON TABLE public.memberships FROM "${APP_ROLE_NAME}";
GRANT SELECT ON TABLE public.memberships TO "${APP_ROLE_NAME}";

-- SITES: APP can read and insert (RLS decides what rows)
REVOKE ALL ON TABLE public.sites FROM "${APP_ROLE_NAME}";
GRANT SELECT, INSERT ON TABLE public.sites TO "${APP_ROLE_NAME}";

-- AUDIT_LOG: APP read-only; writes are server/admin only
REVOKE ALL ON TABLE public.audit_log FROM "${APP_ROLE_NAME}";
GRANT SELECT ON TABLE public.audit_log TO "${APP_ROLE_NAME}";

-- 6) Ensure RLS is enabled + forced on all relevant tables
ALTER TABLE public.orgs        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sites       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log   ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.orgs        FORCE ROW LEVEL SECURITY;
ALTER TABLE public.memberships FORCE ROW LEVEL SECURITY;
ALTER TABLE public.sites       FORCE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log   FORCE ROW LEVEL SECURITY;

-- 7) Quick sanity: show whether the app role bypasses RLS (should be false)
SELECT rolname, rolbypassrls FROM pg_roles WHERE rolname = '${APP_ROLE_NAME}';
SQL

echo "==> Writing corrected DATABASE_URL_APP and DATABASE_URL_MIGRATE into .env.test"
# Replace or append DATABASE_URL_APP / DATABASE_URL_MIGRATE lines
perl -0777 -i -pe '
  my $app = $ENV{APP_URL};
  my $admin = $ENV{DATABASE_URL_ADMIN};
  if ($app !~ /^postgres(ql)?:\/\//) { die "APP_URL is not a valid URL\n"; }
  s/^DATABASE_URL_APP=.*\n//m;
  s/^DATABASE_URL_MIGRATE=.*\n//m;
  $_ .= "DATABASE_URL_APP=\"$app\"\n" unless /DATABASE_URL_APP=/m;
  $_ .= "DATABASE_URL_MIGRATE=\"$admin\"\n" unless /DATABASE_URL_MIGRATE=/m;
' .env.test

echo "==> Verifying APP connection is really the APP role (and not owner/admin)"
set -a
# shellcheck disable=SC1091
source .env.test
set +a

psql "${DATABASE_URL_APP}" -v ON_ERROR_STOP=1 <<SQL
SELECT current_user, session_user;
SELECT rolname, rolbypassrls FROM pg_roles WHERE rolname = current_user;
SELECT relname, relrowsecurity, relforcerowsecurity
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname='public' AND c.relname IN ('orgs','memberships','sites','audit_log')
ORDER BY relname;
SQL

echo "==> Running migrations (admin url via DATABASE_URL_MIGRATE)"
pnpm -s db:migrate

echo "==> Running tests"
pnpm -s test

echo "==> SUCCESS: RLS + privileges restored, tests should now reflect tenant isolation."
