#!/usr/bin/env bash
set -euo pipefail

FILE="docs/BUILD_STATE.md"
MARKER="### Phase 2 Checklist"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: $FILE not found"
  exit 1
fi

if grep -qF "$MARKER" "$FILE"; then
  echo "==> Phase 2 checklist already present (no changes made)"
  exit 0
fi

cat >> "$FILE" <<'MD'

### Phase 2 Checklist

#### Database
- [ ] Confirm `audit_log` remains **append-only** (INSERT by server roles only)
- [ ] Verify app role has **SELECT only** on `audit_log`
- [ ] Add covering indexes for feed queries:
  - [ ] `(org_id, created_at DESC, id DESC)`
  - [ ] `(org_id, entity, entity_id, created_at DESC, id DESC)`
- [ ] Create read-only view `public.v_audit_log_feed`
- [ ] Ensure view relies on base-table RLS (no SECURITY DEFINER)

#### Repository Layer
- [ ] `listAuditFeed({ limit, cursor })`
- [ ] `listEntityAudit({ entity, entityId, limit, cursor })`
- [ ] Stable ordering: `created_at DESC, id DESC`
- [ ] Cursor pagination implemented via `(created_at, id)`

#### Tests
- [ ] Feed returns only current-org rows
- [ ] Non-member sees empty (or guarded error if invalid context)
- [ ] Pagination is stable across identical timestamps
- [ ] Entity filter returns only matching rows
- [ ] Phase 1 tests still pass unchanged

#### Guardrails
- [ ] No new writable tables added
- [ ] No RLS policy weakened
- [ ] No additional app-role privileges granted

#### Exit Criteria
- [ ] `pnpm test` green
- [ ] `pnpm typecheck` green
- [ ] Phase 2 explicitly signed off in BUILD_STATE.md

MD

echo "==> Phase 2 checklist appended to $FILE"
