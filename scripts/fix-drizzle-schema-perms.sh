#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f ".env.test" ]]; then
  echo "ERROR: .env.test not found in $(pwd)"
  exit 1
fi

set -a
source .env.test
set +a

: "${DATABASE_URL_MIGRATE:?ERROR: DATABASE_URL_MIGRATE missing/empty in .env.test}"

if [[ "${DATABASE_URL_MIGRATE}" != postgresql://* && "${DATABASE_URL_MIGRATE}" != postgres://* ]]; then
  echo "ERROR: DATABASE_URL_MIGRATE must be a full postgres URL (postgresql://...)."
  echo "Got: ${DATABASE_URL_MIGRATE}"
  exit 1
fi

command -v psql >/dev/null 2>&1 || { echo "ERROR: psql not found."; exit 1; }

echo "==> Checking schema owners (public/drizzle)"
psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=1 -c \
"select nspname, nspowner::regrole::text as owner
 from pg_namespace
 where nspname in ('public','drizzle')
 order by nspname;"

echo "==> Current user"
psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=1 -c "select current_user, session_user;"

echo "==> Ensuring we can SET ROLE occono_migrate (grant membership if permitted)"
# This may fail if neondb_owner is not allowed to grant membership; we handle that explicitly.
psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=0 -c "grant occono_migrate to neondb_owner;" >/dev/null 2>&1 || true

echo "==> Applying privileges on schema drizzle (as occono_migrate) and ensuring migrations table exists"
psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=1 <<'SQL'
-- Verify whether SET ROLE will work (this will error if membership isn't in place).
set role occono_migrate;

-- Let neondb_owner create/read objects in drizzle schema (needed for drizzle-kit migrate).
grant usage, create on schema drizzle to neondb_owner;

-- Also safe: allow app role to at least use drizzle schema if you want it visible (optional).
-- grant usage on schema drizzle to app_user;

-- Ensure the migrations table exists so drizzle-kit doesn't try to create it and fail.
create table if not exists drizzle.__drizzle_migrations (
  id serial primary key,
  hash text not null,
  created_at bigint
);

reset role;
SQL

echo "==> Verifying neondb_owner now has privileges on drizzle schema"
psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=1 -c \
"select nspname,
        nspowner::regrole::text as owner,
        has_schema_privilege('neondb_owner', nspname, 'USAGE') as owner_has_usage,
        has_schema_privilege('neondb_owner', nspname, 'CREATE') as owner_has_create
 from pg_namespace
 where nspname='drizzle';"

echo "==> DONE: drizzle schema perms fixed. You can now run: pnpm db:migrate"
