import type postgres from "postgres";
import { randomUUID } from "node:crypto";

export type SiteRow = { id: string; org_id: string; name: string };

function assertNonEmpty(v: string, label: string) {
  if (!v?.trim()) throw new Error(`${label} is required`);
}

/**
 * Create a site within the current org.
 *
 * IMPORTANT: This uses APP (RLS enforced). It relies on:
 * - app.user_id + app.org_id being set
 * - the user being a member of the org
 * - org_id matching app.org_id
 */
export async function createSite(
  app: ReturnType<typeof postgres>,
  params: { name: string; orgId: string },
): Promise<SiteRow> {
  assertNonEmpty(params.name, "site.name");
  assertNonEmpty(params.orgId, "orgId");

  const id = randomUUID();

  const rows = await app<SiteRow[]>`
    insert into public.sites (id, org_id, name)
    values (${id}, ${params.orgId}, ${params.name})
    returning id, org_id, name
  `;

  if (!rows[0]) throw new Error("Failed to create site");
  return rows[0];
}

/**
 * List sites visible under RLS for the current org context.
 */
export async function listSites(app: ReturnType<typeof postgres>): Promise<SiteRow[]> {
  return app<SiteRow[]>`
    select id, org_id, name
    from public.sites
    order by name
  `;
}
