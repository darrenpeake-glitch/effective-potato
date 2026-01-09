#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f ".env.test" ]]; then
  echo "ERROR: .env.test not found in $(pwd)"
  exit 1
fi

set -a
source .env.test
set +a

echo "==> Loaded .env.test"
echo "DATABASE_URL_ADMIN present: ${DATABASE_URL_ADMIN:+yes}${DATABASE_URL_ADMIN:-no}"
echo "DATABASE_URL_APP present:   ${DATABASE_URL_APP:+yes}${DATABASE_URL_APP:-no}"
echo "DATABASE_URL_MIGRATE present: ${DATABASE_URL_MIGRATE:+yes}${DATABASE_URL_MIGRATE:-no}"

: "${DATABASE_URL_MIGRATE:?ERROR: DATABASE_URL_MIGRATE is empty after sourcing .env.test}"

if [[ "${DATABASE_URL_MIGRATE}" != postgresql://* && "${DATABASE_URL_MIGRATE}" != postgres://* ]]; then
  echo "ERROR: DATABASE_URL_MIGRATE must be a full postgres URL (postgresql://...)."
  echo "Got: ${DATABASE_URL_MIGRATE}"
  exit 1
fi

command -v psql >/dev/null 2>&1 || { echo "ERROR: psql not found."; exit 1; }

echo "==> Using DATABASE_URL_MIGRATE host:"
python3 - <<'PY'
import os
from urllib.parse import urlparse
u = urlparse(os.environ["DATABASE_URL_MIGRATE"])
print(f"scheme={u.scheme} host={u.hostname} db={u.path.lstrip('/')}")
PY

echo "==> current_user/session_user"
psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=1 -c "select current_user, session_user;"

echo "==> drizzle/public schema owners"
psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=1 -c \
"select nspname, nspowner::regrole::text as owner
 from pg_namespace
 where nspname in ('public','drizzle')
 order by nspname;"

echo "==> DONE"
