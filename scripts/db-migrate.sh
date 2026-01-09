#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f ".env.test" ]]; then
  echo "ERROR: .env.test not found in $(pwd)"
  exit 1
fi

# Load env vars from .env.test into this process
set -a
source .env.test
set +a

: "${DATABASE_URL_MIGRATE:?ERROR: DATABASE_URL_MIGRATE is missing/empty in .env.test}"

# Drizzle config typically reads process.env.DATABASE_URL
export DATABASE_URL="${DATABASE_URL_MIGRATE}"

echo "==> Using DATABASE_URL for drizzle-kit migrate:"
echo "    ${DATABASE_URL%%\?*}"  # print without querystring

pnpm drizzle-kit migrate
