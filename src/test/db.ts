import postgres from "postgres";

function mustEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env var: ${name}`);
  return v;
}

export type SqlClient = ReturnType<typeof postgres>;

export function adminDb(): SqlClient {
  return postgres(mustEnv("DATABASE_URL_ADMIN"), { max: 1 });
}

export function appDb(): SqlClient {
  return postgres(mustEnv("DATABASE_URL_APP"), { max: 5 }); // begin() pins a single connection
}

export async function closeDb(sql: SqlClient) {
  await sql.end({ timeout: 5 });
}

export async function setLocalAppContext(sql: SqlClient, userId: string, orgId: string) {
  // LOCAL (true) is correct inside an explicit transaction
  await sql`select set_config('app.user_id', ${userId}, true)`;
  await sql`select set_config('app.org_id',  ${orgId},  true)`;
}

/**
 * Run a block inside a single transaction+connection with LOCAL session vars set.
 * We intentionally treat the transaction object as a SqlClient (callable template tag),
 * because postgres-js transaction typings are brittle under some TS configs.
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
