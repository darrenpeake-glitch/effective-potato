#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f ".env.test" ]]; then
  echo "ERROR: .env.test not found. Create it first."
  exit 1
fi

set -a
source .env.test
set +a

: "${DATABASE_URL_MIGRATE:?ERROR: DATABASE_URL_MIGRATE missing in .env.test}"

# Locate migrations directory (support both src/db/migrations and db/migrations)
MIG_DIR=""
for d in "src/db/migrations" "db/migrations"; do
  if [[ -d "$d" ]]; then
    MIG_DIR="$d"
    break
  fi
done

if [[ -z "$MIG_DIR" ]]; then
  echo "ERROR: Could not find migrations directory at src/db/migrations or db/migrations"
  exit 1
fi

echo "==> Using migrations dir: $MIG_DIR"
echo

# Find candidate migration files referencing audit_log
mapfile -t files < <(grep -Rnl --include="*.sql" "audit_log" "$MIG_DIR" || true)

if [[ "${#files[@]}" -eq 0 ]]; then
  echo "ERROR: No migration files referencing audit_log found under $MIG_DIR"
  exit 1
fi

echo "==> Found audit_log-related migrations:"
printf "  - %s\n" "${files[@]}"
echo

echo "==> Printing each file with line numbers"
for f in "${files[@]}"; do
  echo
  echo "----- FILE: $f -----"
  nl -ba "$f"
done

echo
echo "==> DB verification (ownership, RLS flags, grants, policies, columns)"
command -v psql >/dev/null 2>&1 || { echo "ERROR: psql not found in PATH"; exit 1; }

psql "$DATABASE_URL_MIGRATE" -v ON_ERROR_STOP=1 -P pager=off <<'SQL'
select current_user, session_user;

-- table shape
\d+ public.audit_log

-- rls flags
select c.relname, c.relrowsecurity, c.relforcerowsecurity, pg_get_userbyid(c.relowner) as owner
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname='public' and c.relname in ('audit_log','orgs','memberships','sites')
order by c.relname;

-- policies
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname='public' and tablename='audit_log'
order by policyname;

-- privileges
select grantee, privilege_type
from information_schema.role_table_grants
where table_schema='public' and table_name='audit_log'
order by grantee, privilege_type;
SQL

echo
echo "==> Done. Paste this script output into chat and I will do the true line-by-line confirmation."
