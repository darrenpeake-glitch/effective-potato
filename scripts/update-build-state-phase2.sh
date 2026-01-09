#!/usr/bin/env bash
set -euo pipefail

FILE="docs/BUILD_STATE.md"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: $FILE not found"
  exit 1
fi

MARKER="## Phase 2 — Audit Read Surface (In Progress)"
if grep -qF "$MARKER" "$FILE"; then
  echo "==> Phase 2 section already present in $FILE (no changes made)"
  exit 0
fi

# Append a Phase 2 section at the end (safe, explicit, minimal risk to existing content).
cat >> "$FILE" <<'MD'

---

## Phase 2 — Audit Read Surface (In Progress)

### Goal
Deliver a **read-only Activity Feed** backed by `public.audit_log` with **no additional write power** granted to the app role.

### Non-negotiable constraints
- **No relaxation of RLS**; continue fail-closed semantics.
- App role remains **SELECT-only** on `audit_log` (and feed views).
- `audit_log` remains **server-only writable** (migrate/service roles only).
- No new tenant-scoped write tables in Phase 2 unless explicitly required.

### Scope (Deliverables)
1. **DB read model**
   - `public.v_audit_log_feed` view (projection over `public.audit_log`, RLS applies at base table)
   - Indexes to support pagination and filtering:
     - `(org_id, created_at desc, id desc)`
     - `(org_id, entity, entity_id, created_at desc, id desc)`
     - optional `(org_id, action, created_at desc)`

2. **Repo layer**
   - `listAuditFeed({ limit, cursor })`
   - `listEntityAudit({ entity, entityId, limit, cursor })`
   - Deterministic ordering: `ORDER BY created_at DESC, id DESC`

3. **Tests**
   - Existing Phase-1 tests continue to pass.
   - Add coverage for:
     - feed ordering stability
     - cursor pagination correctness
     - entity filtering correctness
     - non-member sees empty (or error if invalid context guards apply)

### Definition of Done
- `pnpm test` passes
- `pnpm typecheck` passes
- Feed queries return correct results under RLS
- No new privileges granted to the app role beyond read access for the feed view
MD

echo "==> Updated $FILE with Phase 2 section"
