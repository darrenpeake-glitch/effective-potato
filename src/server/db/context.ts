import type { Sql } from "postgres";
import type postgres from "postgres";

async function setLocalAppContext(sql: Sql, userId: string, orgId: string) {
  // LOCAL (true) is correct inside an explicit transaction
  await sql`select set_config('app.user_id', ${userId}, true)`;
  await sql`select set_config('app.org_id',  ${orgId},  true)`;
}

/**
 * Run a block inside a single transaction+connection with LOCAL session vars set.
 * This matches how you'd implement per-request context in the app layer.
 */
export async function withAppContext<T>(
  app: ReturnType<typeof postgres>,
  userId: string,
  orgId: string,
  fn: (tx: Sql) => Promise<T>,
): Promise<T> {
  return app.begin(async (tx) => {
    // postgres.begin() provides a transaction-scoped sql object that is still a tagged template.
    const typedTx = tx as unknown as Sql;
    await setLocalAppContext(typedTx, userId, orgId);
    return fn(typedTx);
  }) as unknown as T;
}
