import type postgres from "postgres";
import { randomUUID } from "node:crypto";

export type OrgRow = { id: string; name: string };

function assertNonEmpty(v: string, label: string) {
  if (!v?.trim()) throw new Error(`${label} is required`);
}

/**
 * Create an org and make ownerUserId an 'owner' member.
 *
 * This uses ADMIN because orgs/memberships are typically not client-writable.
 */
export async function createOrgWithOwner(
  admin: ReturnType<typeof postgres>,
  params: { name: string; ownerUserId: string },
): Promise<OrgRow> {
  assertNonEmpty(params.name, "org.name");
  assertNonEmpty(params.ownerUserId, "ownerUserId");

  const orgId = randomUUID();
  const membershipId = randomUUID();

  const org = await admin.begin(async (tx) => {
    const created = await tx<OrgRow[]>`
      insert into public.orgs (id, name)
      values (${orgId}, ${params.name})
      returning id, name
    `;
    await tx`
      insert into public.memberships (id, org_id, user_id, role)
      values (${membershipId}, ${orgId}, ${params.ownerUserId}, 'owner')
    `;
    return created[0];
  });

  if (!org) throw new Error("Failed to create org");
  return org;
}

/**
 * Read the currently selected org (as filtered by RLS + app context).
 * Requires app.user_id and app.org_id to be set.
 */
export async function getCurrentOrg(
  app: ReturnType<typeof postgres>,
): Promise<OrgRow | null> {
  const rows = await app<OrgRow[]>`
    select id, name
    from public.orgs
    order by name
    limit 1
  `;
  return rows[0] ?? null;
}
