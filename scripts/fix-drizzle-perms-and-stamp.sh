#!/usr/bin/env bash
set -euo pipefail

APP_ROLE_NAME="${APP_ROLE_NAME:-app_user}"

if [[ ! -f ".env.test" ]]; then
  echo "ERROR: .env.test not found"
  exit 1
fi

set -a
source .env.test
set +a

: "${DATABASE_URL_MIGRATE:?ERROR: DATABASE_URL_MIGRATE missing in .env.test}"

if [[ "${DATABASE_URL_MIGRATE}" != postgresql://* && "${DATABASE_URL_MIGRATE}" != postgres://* ]]; then
  echo "ERROR: DATABASE_URL_MIGRATE must be a full postgres URL (postgresql://...)."
  echo "Got: ${DATABASE_URL_MIGRATE}"
  exit 1
fi

command -v psql >/dev/null 2>&1 || { echo "ERROR: psql not found."; exit 1; }

echo "==> Connecting as DATABASE_URL_MIGRATE to inspect drizzle schema owner"
CURRENT_USER="$(psql "${DATABASE_URL_MIGRATE}" -q -t -A -c 'select current_user;' || true)"
if [[ -z "${CURRENT_USER}" ]]; then
  echo "ERROR: Could not connect with DATABASE_URL_MIGRATE"
  exit 1
fi
echo "==> Connected as: ${CURRENT_USER}"

DRIZZLE_OWNER="$(psql "${DATABASE_URL_MIGRATE}" -q -t -A -c "select n.nspowner::regrole::text from pg_namespace n where n.nspname='drizzle';" || true)"

if [[ -z "${DRIZZLE_OWNER}" ]]; then
  echo "==> Schema drizzle does not exist yet. Creating it (as ${CURRENT_USER})..."
  psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=1 <<SQL
CREATE SCHEMA IF NOT EXISTS drizzle;
SQL
  DRIZZLE_OWNER="$(psql "${DATABASE_URL_MIGRATE}" -q -t -A -c "select n.nspowner::regrole::text from pg_namespace n where n.nspname='drizzle';")"
fi

echo "==> drizzle schema owner: ${DRIZZLE_OWNER}"

echo "==> Attempting to grant perms on schema drizzle to ${CURRENT_USER} and ${APP_ROLE_NAME}"
echo "    (If SET ROLE fails, your migrate user is not a member of the owner role.)"

set +e
psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=1 <<SQL
-- Try to become the owner (required to GRANT on the schema).
SET ROLE "${DRIZZLE_OWNER}";

GRANT USAGE, CREATE ON SCHEMA drizzle TO "${CURRENT_USER}";
GRANT USAGE ON SCHEMA drizzle TO "${APP_ROLE_NAME}";

-- Ensure migrations table exists under drizzle schema.
CREATE TABLE IF NOT EXISTS drizzle.__drizzle_migrations (
  id SERIAL PRIMARY KEY,
  hash text NOT NULL,
  created_at bigint
);

RESET ROLE;
SQL
STATUS=$?
set -e

if [[ $STATUS -ne 0 ]]; then
  cat <<EOF
ERROR: Could not SET ROLE "${DRIZZLE_OWNER}" (or grant permissions).

This means DATABASE_URL_MIGRATE (${CURRENT_USER}) is not allowed to act as the owner role.
You have two options:

1) Update DATABASE_URL_MIGRATE to use credentials for "${DRIZZLE_OWNER}" (the role that owns schema drizzle),
   then rerun this script; OR

2) Drop and recreate the database objects in a database you fully own (so your migrate user owns schema drizzle).

Next diagnostic command to run:
  psql "\$DATABASE_URL_MIGRATE" -c "select current_user, session_user;"

EOF
  exit 1
fi

echo "==> Verifying permissions (schema drizzle)"
psql "${DATABASE_URL_MIGRATE}" -q -c "\dn+ drizzle" || true

echo "==> Now stamping migration history and re-running db:migrate"
bash scripts/stamp-drizzle-migrations.sh

echo "==> DONE"
