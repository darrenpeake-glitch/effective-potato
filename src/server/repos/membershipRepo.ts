import type postgres from "postgres";
import { randomUUID } from "node:crypto";

export type MembershipRow = {
  id: string;
  org_id: string;
  user_id: string;
  role: string;
};

function assertNonEmpty(v: string, label: string) {
  if (!v?.trim()) throw new Error(`${label} is required`);
}

/**
 * Controlled membership creation (server-only).
 * Uses ADMIN because memberships INSERT is blocked under APP/RLS.
 */
export async function addMember(
  admin: ReturnType<typeof postgres>,
  params: {
    orgId: string;
    userId: string;
    role: "owner" | "admin" | "member";
  },
): Promise<MembershipRow> {
  assertNonEmpty(params.orgId, "orgId");
  assertNonEmpty(params.userId, "userId");
  assertNonEmpty(params.role, "role");

  const id = randomUUID();

  const rows = await admin<MembershipRow[]>`
    insert into public.memberships (id, org_id, user_id, role)
    values (${id}, ${params.orgId}, ${params.userId}, ${params.role})
    returning id, org_id, user_id, role
  `;

  if (!rows[0]) throw new Error("Failed to add member");
  return rows[0];
}
