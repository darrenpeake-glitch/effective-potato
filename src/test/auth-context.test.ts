import { describe, it, expect, beforeAll, afterAll } from "vitest";
import postgres from "postgres";
import { adminDb, appDb, closeDb } from "./db";

const ORG_A = "10000000-0000-0000-0000-000000000000";
const USER_A = "00000000-0000-0000-0000-000000000001";

async function withRawContext<T>(
  app: ReturnType<typeof postgres>,
  userId: string,
  orgId: string,
  fn: (tx: ReturnType<typeof postgres>) => Promise<T>,
): Promise<T> {
  return app.begin(async (tx) => {
    await tx`select set_config('app.user_id', ${userId}, true)`;
    await tx`select set_config('app.org_id',  ${orgId},  true)`;
    return fn(tx);
  });
}

describe("Auth context guards", () => {
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

  it("rejects reads when app.user_id points to non-existent user", async () => {
    await expect(
      withRawContext(
        app,
        "00000000-0000-0000-0000-000000000099",
        ORG_A,
        (tx) => tx`select name from public.orgs`,
      ),
    ).rejects.toMatchObject({
      message: expect.stringMatching(/invalid app\.user_id/i),
    });
  });

  it("rejects reads when app.org_id points to non-existent org", async () => {
    await expect(
      withRawContext(
        app,
        USER_A,
        "10000000-0000-0000-0000-000000000099",
        (tx) => tx`select name from public.orgs`,
      ),
    ).rejects.toMatchObject({
      message: expect.stringMatching(/invalid app\.org_id/i),
    });
  });
});
