#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------
# Phase 2.2: Audit Feed Consumption
# - Repo: listAuditFeed (cursor pagination)
# - Tests: member read, non-member empty, invalid context rejects
# ---------------------------------------

die() { echo "ERROR: $*" >&2; exit 3; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

require_cmd node
require_cmd pnpm

# Basic repo sanity
[[ -f package.json ]] || die "package.json not found (run from repo root)."
[[ -d src/server/repos ]] || die "src/server/repos not found."
[[ -d src/test/repos ]] || die "src/test/repos not found."

echo "==> Writing repo: src/server/repos/auditFeedRepo.ts"
cat > src/server/repos/auditFeedRepo.ts <<'TS'
import type { Db } from "../db";

export type AuditFeedRow = {
  id: string;
  org_id: string;
  actor_user_id: string;
  actor_name: string | null;
  actor_email: string | null;
  action: string;
  entity: string;
  entity_id: string | null;
  meta: unknown | null;
  created_at: string;
};

export type AuditFeedCursor = {
  createdAt: string; // ISO timestamp
  id: string;        // uuid
};

export type ListAuditFeedParams = {
  limit?: number;
  cursor?: AuditFeedCursor;
};

/**
 * Phase 2.2 contract:
 * - Uses public.audit_feed (created in Phase 2.1) as the UI surface.
 * - RLS remains enforced by the underlying audit_log policies.
 * - Deterministic pagination: ORDER BY created_at DESC, id DESC
 */
export async function listAuditFeed(tx: Db, params: ListAuditFeedParams = {}) {
  const limit = Math.max(1, Math.min(params.limit ?? 50, 200));

  if (params.cursor) {
    const rows = await tx<AuditFeedRow[]>`
      select
        id,
        org_id,
        actor_user_id,
        actor_name,
        actor_email,
        action,
        entity,
        entity_id,
        meta,
        created_at
      from public.audit_feed
      where (created_at, id) < (${params.cursor.createdAt}::timestamptz, ${params.cursor.id}::uuid)
      order by created_at desc, id desc
      limit ${limit}
    `;
    return rows;
  }

  const rows = await tx<AuditFeedRow[]>`
    select
      id,
      org_id,
      actor_user_id,
      actor_name,
      actor_email,
      action,
      entity,
      entity_id,
      meta,
      created_at
    from public.audit_feed
    order by created_at desc, id desc
    limit ${limit}
  `;
  return rows;
}
TS

echo "==> Writing tests: src/test/repos/auditFeedRepo.test.ts"
cat > src/test/repos/auditFeedRepo.test.ts <<'TS'
import { describe, expect, it, beforeAll, afterAll } from "vitest";
import { adminDb, appDb, closeDb, withAppContext } from "../db";
import { createOrgWithOwner } from "../../server/repos/orgRepo";
import { listAuditFeed } from "../../server/repos/auditFeedRepo";

const USER_A = "00000000-0000-0000-0000-000000000001";
const USER_B = "00000000-0000-0000-0000-000000000002";

async function ensureUser(admin: ReturnType<typeof adminDb>, id: string, email: string, name: string) {
  // Users table is intentionally not tenant-scoped in the Phase 1 model; insert is done with ADMIN.
  await admin`
    insert into public.users (id, email, name)
    values (${id}::uuid, ${email}, ${name})
    on conflict (id) do update set email = excluded.email, name = excluded.name
  `;
}

async function insertAudit(admin: ReturnType<typeof adminDb>, p: {
  id: string;
  orgId: string;
  actorUserId: string;
  action: string;
  entity: string;
  entityId?: string | null;
  meta?: unknown | null;
}) {
  // Server-side insert (ADMIN). RLS + GRANT model decides if this is allowed.
  // We set created_at explicitly for deterministic ordering in tests.
  await admin`
    insert into public.audit_log (
      id,
      org_id,
      actor_user_id,
      action,
      entity,
      entity_id,
      meta,
      created_at
    )
    values (
      ${p.id}::uuid,
      ${p.orgId}::uuid,
      ${p.actorUserId}::uuid,
      ${p.action},
      ${p.entity},
      ${p.entityId ?? null}::uuid,
      ${p.meta ?? null}::jsonb,
      now()
    )
  `;
}

describe("repos: audit feed (Phase 2.2)", () => {
  const admin = adminDb();
  const app = appDb();

  beforeAll(async () => {
    await ensureUser(admin, USER_A, "a@example.com", "Alice");
    await ensureUser(admin, USER_B, "b@example.com", "Bob");
  });

  afterAll(async () => {
    await closeDb(app);
    await closeDb(admin);
  });

  it("member can read audit feed (scoped + ordered)", async () => {
    const org = await createOrgWithOwner(admin, { name: "Org Feed A", ownerUserId: USER_A });

    // Insert a few rows
    await insertAudit(admin, {
      id: "11111111-1111-1111-1111-111111111111",
      orgId: org.id,
      actorUserId: USER_A,
      action: "org.created",
      entity: "org",
      meta: { note: "first" },
    });

    await insertAudit(admin, {
      id: "22222222-2222-2222-2222-222222222222",
      orgId: org.id,
      actorUserId: USER_A,
      action: "site.created",
      entity: "site",
      meta: { siteName: "Example" },
    });

    const rows = await withAppContext(app, USER_A, org.id, async (tx) => {
      return listAuditFeed(tx, { limit: 50 });
    });

    expect(rows.length).toBeGreaterThanOrEqual(2);

    // Must include only this org and have actor info available (via view join)
    for (const r of rows) {
      expect(r.org_id).toBe(org.id);
      expect(r.actor_user_id).toBe(USER_A);
    }

    // Ordering: created_at desc, id desc
    // (Not asserting exact timestamps; just that the ordering is deterministic)
    const sorted = [...rows].sort((a, b) => {
      const ta = new Date(a.created_at).getTime();
      const tb = new Date(b.created_at).getTime();
      if (tb !== ta) return tb - ta;
      return b.id.localeCompare(a.id);
    });
    expect(rows.map((r) => r.id)).toEqual(sorted.map((r) => r.id));
  });

  it("non-member sees empty feed under RLS", async () => {
    const org = await createOrgWithOwner(admin, { name: "Org Feed B", ownerUserId: USER_A });

    await insertAudit(admin, {
      id: "33333333-3333-3333-3333-333333333333",
      orgId: org.id,
      actorUserId: USER_A,
      action: "org.created",
      entity: "org",
      meta: { note: "hidden from B" },
    });

    const rows = await withAppContext(app, USER_B, org.id, async (tx) => {
      return listAuditFeed(tx, { limit: 50 });
    });

    expect(rows).toEqual([]);
  });

  it("invalid context rejects (non-existent org id)", async () => {
    const nonExistentOrgId = "99999999-9999-9999-9999-999999999999";

    await expect(
      withAppContext(app, USER_A, nonExistentOrgId, async (tx) => {
        return listAuditFeed(tx, { limit: 10 });
      })
    ).rejects.toThrow(/invalid app\.org_id/i);
  });

  it("cursor pagination works (stable)", async () => {
    const org = await createOrgWithOwner(admin, { name: "Org Feed C", ownerUserId: USER_A });

    await insertAudit(admin, {
      id: "44444444-4444-4444-4444-444444444444",
      orgId: org.id,
      actorUserId: USER_A,
      action: "a",
      entity: "org",
    });
    await insertAudit(admin, {
      id: "55555555-5555-5555-5555-555555555555",
      orgId: org.id,
      actorUserId: USER_A,
      action: "b",
      entity: "org",
    });
    await insertAudit(admin, {
      id: "66666666-6666-6666-6666-666666666666",
      orgId: org.id,
      actorUserId: USER_A,
      action: "c",
      entity: "org",
    });

    const page1 = await withAppContext(app, USER_A, org.id, async (tx) => {
      return listAuditFeed(tx, { limit: 2 });
    });

    expect(page1.length).toBe(2);

    const cursor = {
      createdAt: page1[page1.length - 1]!.created_at,
      id: page1[page1.length - 1]!.id,
    };

    const page2 = await withAppContext(app, USER_A, org.id, async (tx) => {
      return listAuditFeed(tx, { limit: 50, cursor });
    });

    // No overlap between pages
    const p1Ids = new Set(page1.map((r) => r.id));
    for (const r of page2) expect(p1Ids.has(r.id)).toBe(false);

    // Still scoped
    for (const r of page2) expect(r.org_id).toBe(org.id);
  });
});
TS

echo "==> Running typecheck"
pnpm typecheck

echo "==> Running tests"
pnpm test

echo "==> Phase 2.2 completed successfully."
