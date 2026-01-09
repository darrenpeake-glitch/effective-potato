import type postgres from "postgres";

async function setLocalAppContext(
  sql: ReturnType<typeof postgres>,
  userId: string,
  orgId: string,
) {
  // LOCAL=true is correct inside a transaction (postgres.begin pins one connection).
  await sql`select set_config('app.user_id', ${userId}, true)`;
  await sql`select set_config('app.org_id',  ${orgId},  true)`;
}

/**
 * Run a block inside a single transaction+connection with LOCAL session vars set.
 * This matches per-request context in the app layer.
 */
export async function withAppContext<T>(
  app: ReturnType<typeof postgres>,
  userId: string,
  orgId: string,
  fn: (tx: ReturnType<typeof postgres>) => Promise<T>,
): Promise<T> {
  return app.begin(async (tx) => {
    await setLocalAppContext(tx, userId, orgId);
    return fn(tx);
  });
}
