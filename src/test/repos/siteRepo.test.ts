import { describe, it, expect, beforeAll, afterAll } from "vitest";

import { adminDb, appDb, closeDb } from "../db";
import { withAppContext } from "../helpers";

import { createOrgWithOwner } from "../../server/repos/orgRepo";
import { addMember } from "../../server/repos/membershipRepo";
import { createSite, listSites } from "../../server/repos/siteRepo";

const USER_A = "00000000-0000-0000-0000-000000000001";
const USER_B = "00000000-0000-0000-0000-000000000002";
const USER_C = "00000000-0000-0000-0000-000000000003";

describe("repos: sites (APP-writable under RLS)", () => {
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

  it("member can insert + list sites in-org", async () => {
    const org = await createOrgWithOwner(admin, { name: "Org Sites A", ownerUserId: USER_A });
    await addMember(admin, { orgId: org.id, userId: USER_B, role: "member" });

    const created = await withAppContext(app, USER_B, org.id, async (tx) => {
      return createSite(tx, { orgId: org.id, name: "Site 1" });
    });

    expect(created.name).toBe("Site 1");
    expect(created.org_id).toBe(org.id);

    const rows = await withAppContext(app, USER_B, org.id, async (tx) => {
      return listSites(tx);
    });

    expect(rows.map(r => r.name)).toEqual(["Site 1"]);
  });

  it("non-member cannot see sites (RLS filters to empty)", async () => {
    const org = await createOrgWithOwner(admin, { name: "Org Sites B", ownerUserId: USER_A });

    // Owner inserts via APP context (allowed)
    await withAppContext(app, USER_A, org.id, async (tx) => {
      await createSite(tx, { orgId: org.id, name: "Hidden Site" });
    });

    // USER_C is not a member
    const rows = await withAppContext(app, USER_C, org.id, async (tx) => {
      return listSites(tx);
    });

    expect(rows).toEqual([]);
  });

  it("non-member cannot insert sites (RLS rejects)", async () => {
    const org = await createOrgWithOwner(admin, { name: "Org Sites C", ownerUserId: USER_A });

    await expect(
      withAppContext(app, USER_C, org.id, async (tx) => {
        await createSite(tx, { orgId: org.id, name: "Should Fail" });
      })
    ).rejects.toThrow(/row-level security|permission denied/i);
  });

  it("cross-tenant isolation: member of Org1 cannot see Org2 sites even if org_id context points to Org2", async () => {
    const org1 = await createOrgWithOwner(admin, { name: "Org One", ownerUserId: USER_A });
    const org2 = await createOrgWithOwner(admin, { name: "Org Two", ownerUserId: USER_C });

    // USER_B is member only of org1
    await addMember(admin, { orgId: org1.id, userId: USER_B, role: "member" });

    // Seed a site in org2 as its owner
    await withAppContext(app, USER_C, org2.id, async (tx) => {
      await createSite(tx, { orgId: org2.id, name: "Org2 Site" });
    });

    // Now USER_B tries to set context to org2
    const rows = await withAppContext(app, USER_B, org2.id, async (tx) => {
      return listSites(tx);
    });

    // Must be empty (or error if your guards enforce "valid context" strictly).
    expect(rows).toEqual([]);
  });
});
