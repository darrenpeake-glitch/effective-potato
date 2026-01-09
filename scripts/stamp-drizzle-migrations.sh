#!/usr/bin/env bash
set -euo pipefail

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
command -v node >/dev/null 2>&1 || { echo "ERROR: node not found."; exit 1; }

JOURNAL="src/db/migrations/meta/_journal.json"
META_DIR="src/db/migrations/meta"

if [[ ! -f "${JOURNAL}" ]]; then
  echo "ERROR: Missing ${JOURNAL}"
  exit 1
fi

echo "==> Ensuring drizzle schema + migrations table exists"
psql "${DATABASE_URL_MIGRATE}" -v ON_ERROR_STOP=1 <<'SQL'
CREATE SCHEMA IF NOT EXISTS drizzle;
CREATE TABLE IF NOT EXISTS drizzle.__drizzle_migrations (
  id SERIAL PRIMARY KEY,
  hash text NOT NULL,
  created_at bigint
);
SQL

echo "==> Reading journal + stamping hashes into drizzle.__drizzle_migrations (idempotent)"
node <<'NODE'
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const journalPath = "src/db/migrations/meta/_journal.json";
const metaDir = "src/db/migrations/meta";
const journal = JSON.parse(fs.readFileSync(journalPath, "utf8"));

if (!journal.entries || !Array.isArray(journal.entries)) {
  throw new Error("Unexpected journal format: missing entries[]");
}

function runPsql(sql) {
  const env = { ...process.env };
  const res = spawnSync("psql", [env.DATABASE_URL_MIGRATE, "-v", "ON_ERROR_STOP=1", "-q", "-t", "-A", "-c", sql], {
    stdio: ["ignore", "pipe", "pipe"],
    env,
  });
  if (res.status !== 0) {
    const err = res.stderr.toString("utf8");
    throw new Error(`psql failed:\n${err}`);
  }
  return res.stdout.toString("utf8").trim();
}

let stamped = 0;
let skipped = 0;

for (const e of journal.entries) {
  const tag = e.tag;
  if (!tag || typeof tag !== "string") continue;

  const snapPath = path.join(metaDir, `${tag}_snapshot.json`);
  if (!fs.existsSync(snapPath)) {
    console.warn(`WARN: snapshot missing for tag ${tag}: ${snapPath}`);
    continue;
  }
  const snap = JSON.parse(fs.readFileSync(snapPath, "utf8"));
  const hash = snap.id;
  if (!hash || typeof hash !== "string") {
    console.warn(`WARN: snapshot id missing for tag ${tag}`);
    continue;
  }

  // Check if already present
  const exists = runPsql(`select 1 from drizzle.__drizzle_migrations where hash='${hash.replace(/'/g,"''")}' limit 1;`);
  if (exists === "1") {
    skipped++;
    continue;
  }

  const now = Date.now();
  runPsql(`insert into drizzle.__drizzle_migrations(hash, created_at) values ('${hash.replace(/'/g,"''")}', ${now});`);
  stamped++;
}

console.log(`Stamped: ${stamped}  |  Already present: ${skipped}`);
NODE

echo "==> Running db:migrate again (should now be clean)"
pnpm -s db:migrate

echo "==> DONE (migration history stamped)"
