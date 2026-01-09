import { describe, it, expect, beforeAll, afterAll } from "vitest";

import { adminDb, appDb, closeDb } from "../db";
import { withAppContext } from "../helpers";

import { createOrgWithOwner } from "../../server/repos/orgRepo";
import { addMember } from "../../server/repos/membershipRepo";
import { appendAudit, listAudit } from "../../server/repos/auditRepo";

const USER_A = "00000000-0000-0000-0000-000000000001";
const USER_B = "00000000-0000-0000-0000-000000000002";
const USER_C = "00000000-0000-0000-0000-000000000003";

describe("repos: audit log (append-only, server write)", () => {
  const admin = adminDb();
  const app = appDb();

  beforeAll(async () => {
    await admin`delete from public.audit_log`;
    await admin`delete from public.sites`;
    await admin`delete from public.memberships`;
    await admin`delete from public.orgs`;
    await admin`delete from public.users`;

    await admin`insert into public.users (id, email) values (${USER_A}, 'a@example.com')`;
    await admin`insert into public.users (id, email) values (${USER_B}, 'b@example.com')`;
    await admin`insert into public.users (id, email) values (${USER_C}, 'c@example.com')`;
  });

  afterAll(async () => {
    await closeDb(app);
    await closeDb(admin);
  });

  it("server can append audit; member can read under RLS", async () => {
    const org = await createOrgWithOwner(admin, { name: "Org Audit", ownerUserId: USER_A });
    await addMember(admin, { orgId: org.id, userId: USER_B, role: "member" });

    await appendAudit(admin, {
      orgId: org.id,
      action: "site.created",
      actorUserId: USER_A,
      meta: { siteName: "Example" },
    });

    const rows = await withAppContext(app, USER_B, org.id, async (tx) => {
      return listAudit(tx);
    });

    expect(rows.length).toBe(1);
    expect(rows[0].action).toBe("site.created");
    expect(rows[0].org_id).toBe(org.id);
  });

  it("non-member cannot read audit rows (RLS filters to empty)", async () => {
    const org = await createOrgWithOwner(admin, { name: "Org Audit 2", ownerUserId: USER_A });

    await appendAudit(admin, { orgId: org.id, action: "org.created", actorUserId: USER_A });

    const rows = await withAppContext(app, USER_C, org.id, async (tx) => {
      return listAudit(tx);
    });

    expect(rows).toEqual([]);
  });

  it("APP cannot write audit_log (GRANT/RLS)", async () => {
    const org = await createOrgWithOwner(admin, { name: "Org Audit 3", ownerUserId: USER_A });

    await expect(
      withAppContext(app, USER_A, org.id, async (tx) => {
        await tx`
          insert into public.audit_log (id, org_id, action)
          values ('99999999-9999-9999-9999-999999999999', ${org.id}, 'should.fail')
        `;
      })
    ).rejects.toThrow(/permission denied|row-level security/i);
  });
});
