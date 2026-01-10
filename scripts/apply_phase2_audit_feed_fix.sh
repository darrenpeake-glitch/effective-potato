#!/usr/bin/env bash
set -euo pipefail

# Must run from repo root
if [[ ! -f "./package.json" ]]; then
  echo "ERROR: run this from the repo root (package.json not found)" >&2
  exit 1
fi

REPO_FILE="src/server/repos/auditFeedRepo.ts"
BUILD_STATE="docs/BUILD_STATE.md"

echo "→ Writing $REPO_FILE"

cat > "$REPO_FILE" <<'TS'
import type { Db } from "../db";

export type AuditFeedRow = {
  id: string;
  org_id: string;
  actor_user_id: string;
  actor_name: string | null;
  actor_email: string | null;
  action: string;
  entity: string;
  entity_id: string | null;
  meta: unknown | null;
  created_at: string;
};

export type AuditFeedCursor = {
  createdAt: string;
  id: string;
};

export type ListAuditFeedParams = {
  limit?: number;
  cursor?: AuditFeedCursor;
};

export type ListEntityAuditParams = {
  entity: string;
  entityId: string;
  limit?: number;
  cursor?: AuditFeedCursor;
};

export async function listAuditFeed(tx: Db, params: ListAuditFeedParams = {}) {
  const limit = Math.max(1, Math.min(params.limit ?? 50, 200));

  await tx`select public.require_valid_org();`;
  await tx`select public.require_valid_user();`;

  if (params.cursor) {
    return tx<AuditFeedRow[]>`
      select *
      from public.v_audit_log_feed
      where org_id = public.app_org_id()
        and public.is_org_member(org_id)
        and (created_at, id) <
            (${params.cursor.createdAt}::timestamptz, ${params.cursor.id}::uuid)
      order by created_at desc, id desc
      limit ${limit}
    `;
  }

  return tx<AuditFeedRow[]>`
    select *
    from public.v_audit_log_feed
    where org_id = public.app_org_id()
      and public.is_org_member(org_id)
    order by created_at desc, id desc
    limit ${limit}
  `;
}

export async function listEntityAudit(tx: Db, params: ListEntityAuditParams) {
  const limit = Math.max(1, Math.min(params.limit ?? 50, 200));

  await tx`select public.require_valid_org();`;
  await tx`select public.require_valid_user();`;

  if (params.cursor) {
    return tx<AuditFeedRow[]>`
      select *
      from public.v_audit_log_feed
      where org_id = public.app_org_id()
        and public.is_org_member(org_id)
        and entity = ${params.entity}
        and entity_id = ${params.entityId}
        and (created_at, id) <
            (${params.cursor.createdAt}::timestamptz, ${params.cursor.id}::uuid)
      order by created_at desc, id desc
      limit ${limit}
    `;
  }

  return tx<AuditFeedRow[]>`
    select *
    from public.v_audit_log_feed
    where org_id = public.app_org_id()
      and public.is_org_member(org_id)
      and entity = ${params.entity}
      and entity_id = ${params.entityId}
    order by created_at desc, id desc
    limit ${limit}
  `;
}
TS

echo "→ Updating $BUILD_STATE"

TODAY="$(date +%Y-%m-%d)"
TMP="$(mktemp)"

awk -v today="$TODAY" '
/^Last updated:/ { print "Last updated: " today; next }
{ print }
' "$BUILD_STATE" > "$TMP"

mv "$TMP" "$BUILD_STATE"

echo "✓ Phase 2.3 applied"
