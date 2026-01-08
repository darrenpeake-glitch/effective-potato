import postgres from "postgres";

function mustEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env var: ${name}`);
  return v;
}

export function adminDb() {
  return postgres(mustEnv("DATABASE_URL_ADMIN"), { max: 1 });
}

export function appDb() {
  return postgres(mustEnv("DATABASE_URL_APP"), { max: 1 });
}

export async function closeDb(sql: ReturnType<typeof postgres>) {
  await sql.end({ timeout: 5 });
}

/**
 * Sets request-scoped context vars for RLS in the *current* transaction/connection.
 * We keep it explicit and "LOCAL" (true) so it is scoped to transaction/session.
 */
export async function setAppContext(
  sql: ReturnType<typeof postgres>,
  userId: string,
  orgId: string,
) {
  await sql`select set_config('app.user_id', ${userId}, true)`;
  await sql`select set_config('app.org_id', ${orgId}, true)`;
}
