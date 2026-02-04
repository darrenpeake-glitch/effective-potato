import crypto from "crypto";
import type { Db } from "../db";

export type AuditRow = {
  id: string;
  org_id: string;
  entity: string;
  action: string;
  actor_user_id: string;
  actor_name: string | null;
  actor_email: string | null;
  meta: unknown | null;
  created_at: string;
};

/**
 * Append-only audit log.
 * - MUST be called with admin/service connection (bypasses RLS)
 * - actor_user_id is required by schema
 * - entity defaults to "org"
 *
 * Phase 3:
 * - snapshots actor_name + actor_email at write time (no joins at read time)
 */
export async function appendAudit(
  admin: Db,
  params: {
    orgId: string;
    action: string;
    actorUserId: string; // required
    entity?: string;
    entityId?: string | null;
    meta?: unknown;
  },
): Promise<AuditRow> {
  const id = crypto.randomUUID();

  const actor = params.actorUserId;

  // Phase 3: snapshot actor identity at write time (no joins at read time).
  const u = await admin<{ name: string | null; email: string | null }[]>`
    select name, email
    from public.users
    where id = ${actor}::uuid
    limit 1
  `;
  const actorName = u[0]?.name ?? null;
  const actorEmail = u[0]?.email ?? null;

  const meta = params.meta ?? null;
  const entity = params.entity ?? "org";
  const entityId = params.entityId ?? null;

  const rows = await admin<AuditRow[]>`
    insert into public.audit_log (
      id,
      org_id,
      entity,
      entity_id,
      action,
      actor_user_id,
      actor_name,
      actor_email,
      meta
    )
    values (
      ${id},
      ${params.orgId},
      ${entity},
      ${entityId},
      ${params.action},
      ${actor},
      ${actorName},
      ${actorEmail},
      ${meta as any}
    )
    returning
      id,
      org_id,
      entity,
      action,
      actor_user_id,
      actor_name,
      actor_email,
      meta,
      created_at
  `;

  return rows[0]!;
}

/**
 * Read audit rows for the current org under RLS.
 * - MUST be called with app connection (RLS enforced)
 *
 * Note: Feed reads should use auditFeedRepo + v_audit_log_feed.
 */
export async function listAudit(
  app: Db,
  opts?: { limit?: number },
): Promise<AuditRow[]> {
  const limit = Math.min(Math.max(opts?.limit ?? 100, 1), 500);

  return app<AuditRow[]>`
    select
      id,
      org_id,
      entity,
      action,
      actor_user_id,
      actor_name,
      actor_email,
      meta,
      created_at
    from public.audit_log
    order by created_at desc, id desc
    limit ${limit}
  `;
}
