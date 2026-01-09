import { describe, it, expect, beforeAll, afterAll } from "vitest";

// Use your existing test DB helpers.
// If your repo has these in different locations, adjust only these two import paths.
import { adminDb, appDb, closeDb } from "../db";
import { withAppContext } from "../helpers";

import { createOrgWithOwner, getCurrentOrg } from "../../server/repos/orgRepo";
import { addMember } from "../../server/repos/membershipRepo";

const USER_A = "00000000-0000-0000-0000-000000000001";
const USER_B = "00000000-0000-0000-0000-000000000002";

describe("repos: org + membership (RLS-backed)", () => {
  const admin = adminDb();
  const app = appDb();

  beforeAll(async () => {
    // Clean slate (order matters due to FKs in later phases; safe now anyway)
    await admin`delete from public.audit_log`;
    await admin`delete from public.sites`;
    await admin`delete from public.memberships`;
    await admin`delete from public.orgs`;
    await admin`delete from public.users`;

    // Seed users
    await admin`insert into public.users (id, email) values (${USER_A}, 'a@example.com')`;
    await admin`insert into public.users (id, email) values (${USER_B}, 'b@example.com')`;
  });

  afterAll(async () => {
    await closeDb(app);
    await closeDb(admin);
  });

  it("createOrgWithOwner creates org + owner membership; APP can read current org under RLS", async () => {
    const org = await createOrgWithOwner(admin, { name: "Org A", ownerUserId: USER_A });
    expect(org.name).toBe("Org A");

    const visible = await withAppContext(app, USER_A, org.id, async (tx) => {
      return getCurrentOrg(tx);
    });

    expect(visible?.id).toBe(org.id);
    expect(visible?.name).toBe("Org A");
  });

  it("addMember grants access for second user under RLS", async () => {
    const org = await createOrgWithOwner(admin, { name: "Org B", ownerUserId: USER_A });
    await addMember(admin, { orgId: org.id, userId: USER_B, role: "member" });

    const visibleForB = await withAppContext(app, USER_B, org.id, async (tx) => {
      return getCurrentOrg(tx);
    });

    expect(visibleForB?.name).toBe("Org B");
  });

  it("non-member cannot read org under RLS (fail-closed)", async () => {
    const org = await createOrgWithOwner(admin, { name: "Org C", ownerUserId: USER_A });

    const visibleForB = await withAppContext(app, USER_B, org.id, async (tx) => {
      return getCurrentOrg(tx);
    });

    expect(visibleForB).toBeNull();
  });
});
