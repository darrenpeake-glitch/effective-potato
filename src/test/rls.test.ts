import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { adminDb, appDb, closeDb, setAppContext } from "./db";

const ORG_A = "10000000-0000-0000-0000-000000000000";
const ORG_B = "10000000-0000-0000-0000-000000000001";

const USER_A = "00000000-0000-0000-0000-000000000001";
const USER_B = "00000000-0000-0000-0000-000000000002";

describe("RLS (fail-closed + tenant isolation)", () => {
  const admin = adminDb();
  const app = appDb();

  beforeAll(async () => {
    // Clean & seed with admin (bypasses RLS)
    await admin`delete from public.audit_log`;
    await admin`delete from public.sites`;
    await admin`delete from public.memberships`;
    await admin`delete from public.orgs`;
    await admin`delete from public.users`;

    await admin`
      insert into public.users (id, email)
      values
        (${USER_A}, 'usera@example.com'),
        (${USER_B}, 'userb@example.com')
    `;

    await admin`
      insert into public.orgs (id, name)
      values
        (${ORG_A}, 'Org A'),
        (${ORG_B}, 'Org B')
    `;

    await admin`
      insert into public.memberships (id, org_id, user_id, role)
      values
        ('20000000-0000-0000-0000-000000000000', ${ORG_A}, ${USER_A}, 'owner'),
        ('20000000-0000-0000-0000-000000000001', ${ORG_B}, ${USER_B}, 'owner')
    `;

    await admin`
      insert into public.sites (id, org_id, name)
      values
        ('30000000-0000-0000-0000-000000000000', ${ORG_A}, 'Site A1'),
        ('30000000-0000-0000-0000-000000000001', ${ORG_B}, 'Site B1')
    `;
  });

  afterAll(async () => {
    await closeDb(app);
    await closeDb(admin);
  });

  it("fails closed without app.user_id/app.org_id", async () => {
    const rows = await app<{ count: number }[]>`select count(*)::int as count from public.orgs`;
    expect(rows[0].count).toBe(0);
  });

  it("allows access to current org when context is set and membership exists", async () => {
    await setAppContext(app, USER_A, ORG_A);
    const rows = await app<{ name: string }[]>`select name from public.orgs order by name`;
    expect(rows.map(r => r.name)).toEqual(["Org A"]);
  });

  it("prevents cross-tenant reads (Org A user cannot see Org B site)", async () => {
    await setAppContext(app, USER_A, ORG_A);
    const rows = await app<{ name: string }[]>`select name from public.sites order by name`;
    expect(rows.map(r => r.name)).toEqual(["Site A1"]);
  });

  it("prevents writes to orgs table (policies are false)", async () => {
    await setAppContext(app, USER_A, ORG_A);
    await expect(
      app`insert into public.orgs (id, name) values ('11111111-1111-1111-1111-111111111111', 'Nope')`
    ).rejects.toThrow();
  });

  it("allows in-org site inserts when member", async () => {
    await setAppContext(app, USER_A, ORG_A);
    await app`
      insert into public.sites (id, org_id, name)
      values ('30000000-0000-0000-0000-000000000010', ${ORG_A}, 'Site A2')
    `;

    const rows = await app<{ name: string }[]>`select name from public.sites order by name`;
    expect(rows.map(r => r.name)).toEqual(["Site A1", "Site A2"]);
  });
});
