import type { SqlClient } from "./db";
import { setLocalAppContext } from "./db";

/**
 * Some tests use a local helper; keep it consistent with src/test/db.ts.
 */
export async function withAppContext<T>(
  app: SqlClient,
  userId: string,
  orgId: string,
  fn: (tx: SqlClient) => Promise<T> | T,
): Promise<T> {
  const result = await app.begin(async (tx) => {
    const sql = tx as unknown as SqlClient;
    await setLocalAppContext(sql, userId, orgId);
    return await fn(sql);
  });

  return result as unknown as T;
}
