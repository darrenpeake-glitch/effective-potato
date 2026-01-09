#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Ensuring .env.test exists"
if [[ ! -f .env.test ]]; then
  cat > .env.test <<'ENV'
# Fill these in with your real connection strings.
# Example:
# DATABASE_URL_ADMIN="postgres://user:pass@host:5432/db?sslmode=require"
# DATABASE_URL_APP="postgres://user:pass@host:5432/db?sslmode=require"
# DATABASE_URL_MIGRATE="postgres://user:pass@host:5432/db?sslmode=require"
DATABASE_URL_ADMIN=""
DATABASE_URL_APP=""
DATABASE_URL_MIGRATE=""
ENV
  echo "Created .env.test (EMPTY). Populate it, then re-run this script."
  exit 1
fi

# Ensure not empty
missing=0
for k in DATABASE_URL_ADMIN DATABASE_URL_APP DATABASE_URL_MIGRATE; do
  v="$(grep -E "^${k}=" .env.test | head -n1 | cut -d= -f2- | tr -d '"' || true)"
  if [[ -z "${v}" ]]; then
    echo "ERROR: ${k} is empty in .env.test"
    missing=1
  fi
done
if [[ $missing -eq 1 ]]; then
  echo ""
  echo "Populate .env.test with your real URLs and re-run:"
  echo "  bash scripts/setup-tests.sh"
  exit 1
fi

echo "==> Installing dotenv-cli (dev dependency)"
pnpm add -D dotenv-cli

echo "==> Updating package.json scripts (test + test:db)"
node - <<'NODE'
const fs = require('fs');

const pkgPath = 'package.json';
const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
pkg.scripts ||= {};

pkg.scripts.test = "dotenv -e .env.test -- vitest run";
pkg.scripts["test:db"] = "dotenv -e .env.test -- pnpm db:migrate && dotenv -e .env.test -- vitest run";

fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + "\n");
console.log("Updated package.json scripts: test, test:db");
NODE

echo "==> Verifying env is visible to node under dotenv"
pnpm -s dotenv -e .env.test -- node -e "console.log('DATABASE_URL_ADMIN set:', !!process.env.DATABASE_URL_ADMIN)"

echo "==> Running migrations + tests"
pnpm -s test:db

echo "==> Done"
