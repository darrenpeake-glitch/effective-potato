import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { adminDb, appDb, closeDb, withAppContext } from "./db";

const USER_A = "20000000-0000-0000-0000-000000000001";

describe("Auth context guards", () => {
  const admin = adminDb();
  const app = appDb();

  beforeAll(async () => {
    // Ensure clean slate
    await admin`delete from public.audit_log`;
    await admin`delete from public.memberships`;
    await admin`delete from public.sites`;
    await admin`delete from public.orgs`;
    await admin`delete from public.users`;

    // Seed a user + org
    await admin`
      insert into public.users (id, email)
      values (${USER_A}, 'a@example.com')
    `;

    await admin`
      insert into public.orgs (id, name)
      values ('10000000-0000-0000-0000-000000000001', 'Org A')
    `;

    await admin`
      insert into public.memberships (org_id, user_id, role)
      values ('10000000-0000-0000-0000-000000000001', ${USER_A}, 'owner')
    `;
  });

  afterAll(async () => {
    await closeDb(app);
    await closeDb(admin);
  });

  it("rejects reads when app.org_id points to non-existent org", async () => {
    // If your DB guard function throws on invalid org_id, this test should expect a throw.
    // If you chose the 'silent empty' model instead, then update expectation accordingly.
    await expect(
      app.begin(async (tx) => {
        const sql = tx as any;
        await sql`select set_config('app.user_id', ${USER_A}::text, false)`;
        await sql`select set_config('app.org_id',  '10000000-0000-0000-0000-000000000099', false)`;
        return sql`select name from public.orgs`;
      }),
    ).rejects.toThrow(/invalid app\.org_id/i);
  });

  it("allows reads when context is valid", async () => {
    const rows = await withAppContext(
      app,
      USER_A,
      "10000000-0000-0000-0000-000000000001",
      (tx) => tx<{ name: string }[]>`select name from public.orgs`,
    );
    expect(rows.map((r) => r.name)).toEqual(["Org A"]);
  });
});
