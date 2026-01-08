import postgres from "postgres";

function mustEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env var: ${name}`);
  return v;
}

function makeSql(url: string, max: number) {
  return postgres(url, {
    max,
    prepare: false, // reduce test flakiness; no server-prepared statements
    onnotice: () => {}, // keep CI output clean
  });
}

export function adminDb() {
  return makeSql(mustEnv("DATABASE_URL_ADMIN"), 1);
}

export function appDb() {
  // begin() pins a single connection; pool max>1 is fine
  return makeSql(mustEnv("DATABASE_URL_APP"), 5);
}

export async function closeDb(sql: ReturnType<typeof postgres>) {
  await sql.end({ timeout: 5 });
}

async function setLocalAppContext(
  sql: ReturnType<typeof postgres>,
  userId: string,
  orgId: string,
) {
  // LOCAL (true) is correct *inside an explicit transaction*
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
  fn: (tx: ReturnType<typeof postgres>) => Promise<T>,
): Promise<T> {
  return app.begin(async (tx) => {
    await setLocalAppContext(tx, userId, orgId);
    return fn(tx);
  });
}
