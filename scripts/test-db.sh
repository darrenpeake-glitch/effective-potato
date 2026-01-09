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
: "${DATABASE_URL_ADMIN:?ERROR: DATABASE_URL_ADMIN missing/empty in .env.test}"
: "${DATABASE_URL_APP:?ERROR: DATABASE_URL_APP missing/empty in .env.test}"

# For drizzle-kit migrate:
export DATABASE_URL="${DATABASE_URL_MIGRATE}"

echo "==> Migrating"
pnpm drizzle-kit migrate

echo "==> Running tests"
pnpm test
