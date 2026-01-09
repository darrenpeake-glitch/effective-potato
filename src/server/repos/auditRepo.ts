import crypto from "crypto";

export type AuditRow = {
  id: string;
  org_id: string;
  entity: string;
  action: string;
  actor_user_id: string | null;
  meta: unknown | null;
  created_at: string;
};

/**
 * Append-only audit log.
 * - MUST be called with admin/service connection (bypasses RLS)
 * - entity is REQUIRED by schema (default: "org")
 */
export async function appendAudit(
  admin: any,
  params: {
    orgId: string;
    action: string;
    actorUserId?: string | null;
    entity?: string;
    meta?: unknown;
  },
): Promise<AuditRow> {
  const id = crypto.randomUUID();
  const actor = params.actorUserId ?? null;
  const meta = params.meta ?? null;
  const entity = params.entity ?? "org";

  const rows = await admin<AuditRow[]>`
    insert into public.audit_log (
      id,
      org_id,
      entity,
      action,
      actor_user_id,
      meta
    )
    values (
      ${id},
      ${params.orgId},
      ${entity},
      ${params.action},
      ${actor},
      ${meta as any}
    )
    returning *
  `;

  return rows[0]!;
}

/**
 * Read audit rows for the current org under RLS.
 * - MUST be called with app connection (RLS enforced)
 * - Uses app.org_id + membership checks via policies
 */
export async function listAudit(
  app: any,
  opts?: { limit?: number },
): Promise<AuditRow[]> {
  const limit = Math.min(Math.max(opts?.limit ?? 100, 1), 500);

  return app<AuditRow[]>`
    select id, org_id, entity, action, actor_user_id, meta, created_at
    from public.audit_log
    order by created_at desc
    limit ${limit}
  `;
}
