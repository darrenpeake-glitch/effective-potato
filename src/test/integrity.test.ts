import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { adminDb, appDb, closeDb, withAppContext } from "./db";

const ORG_A = "10000000-0000-0000-0000-000000000000";
const USER_A = "00000000-0000-0000-0000-000000000001";

describe("DB integrity (constraints)", () => {
  const admin = adminDb();
  const app = appDb();

  beforeAll(async () => {
    await admin`delete from public.audit_log`;
    await admin`delete from public.sites`;
    await admin`delete from public.memberships`;
    await admin`delete from public.orgs`;
    await admin`delete from public.users`;

    await admin`insert into public.users (id, email) values (${USER_A}, 'usera@example.com')`;
    await admin`insert into public.orgs (id, name) values (${ORG_A}, 'Org A')`;
    await admin`
      insert into public.memberships (id, org_id, user_id, role)
      values ('20000000-0000-0000-0000-000000000000', ${ORG_A}, ${USER_A}, 'owner')
    `;
  });

  afterAll(async () => {
    await closeDb(app);
    await closeDb(admin);
  });

  it("rejects duplicate memberships (org_id,user_id)", async () => {
    await expect(
      admin`
        insert into public.memberships (id, org_id, user_id, role)
        values ('20000000-0000-0000-0000-000000000099', ${ORG_A}, ${USER_A}, 'owner')
      `
    ).rejects.toMatchObject({ message: expect.stringMatching(/duplicate|unique/i) });
  });

  it("rejects invalid membership roles", async () => {
    await expect(
      admin`
        insert into public.memberships (id, org_id, user_id, role)
        values ('20000000-0000-0000-0000-000000000098', ${ORG_A}, '00000000-0000-0000-0000-000000000099', 'superadmin')
      `
    ).rejects.toMatchObject({ message: expect.stringMatching(/check constraint|violates/i) });
  });
});
