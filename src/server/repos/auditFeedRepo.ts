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
  createdAt: string; // ISO timestamp
  id: string;        // uuid
};

export type ListAuditFeedParams = {
  limit?: number;
  cursor?: AuditFeedCursor;
};

/**
 * Phase 2.2:
 * - Read from public.audit_feed (Phase 2.1 view).
 * - Deterministic pagination ORDER BY created_at DESC, id DESC.
 */
export async function listAuditFeed(tx: Db, params: ListAuditFeedParams = {}) {
  const limit = Math.max(1, Math.min(params.limit ?? 50, 200));

  if (params.cursor) {
    const rows = await tx<AuditFeedRow[]>`
      select
        id,
        org_id,
        actor_user_id,
        actor_name,
        actor_email,
        action,
        entity,
        entity_id,
        meta,
        created_at
      from public.audit_feed
      where (created_at, id) < (${params.cursor.createdAt}::timestamptz, ${params.cursor.id}::uuid)
      order by created_at desc, id desc
      limit ${limit}
    `;
    return rows;
  }

  const rows = await tx<AuditFeedRow[]>`
    select
      id,
      org_id,
      actor_user_id,
      actor_name,
      actor_email,
      action,
      entity,
      entity_id,
      meta,
      created_at
    from public.audit_feed
    order by created_at desc, id desc
    limit ${limit}
  `;
  return rows;
}
