import type { SqlClient } from "../../test/db";
import crypto from "node:crypto";

export type OrgRow = {
  id: string;
  name: string;
  created_at: string;
};

type CreateOrgParams = {
  name: string;
  ownerUserId: string;
  orgId?: string; // optional for tests / deterministic fixtures
};

export async function createOrgWithOwner(admin: SqlClient, params: CreateOrgParams) {
  const orgId = params.orgId ?? crypto.randomUUID();

  await admin`
    insert into public.orgs (id, name)
    values (${orgId}, ${params.name})
  `;

  await admin`
    insert into public.memberships (org_id, user_id, role)
    values (${orgId}, ${params.ownerUserId}, 'owner')
  `;

  const rows = await admin<OrgRow[]>`
    select id, name, created_at
    from public.orgs
    where id = ${orgId}
  `;

  return rows[0]!;
}

export async function getCurrentOrg(tx: SqlClient) {
  const rows = await tx<OrgRow[]>`
    select id, name, created_at
    from public.orgs
    where id = public.app_org_id()
  `;
  return rows[0] ?? null;
}
