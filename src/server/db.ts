import postgres from "postgres";

function mustEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env var: ${name}`);
  return v;
}

/**
 * ADMIN connection: privileged (server-only). Use for controlled writes that the APP role cannot do.
 */
export function adminDb() {
  return postgres(mustEnv("DATABASE_URL_ADMIN"), { max: 1 });
}

/**
 * APP connection: RLS-enforced role. Use for queries that must respect tenant isolation.
 */
export function appDb() {
  return postgres(mustEnv("DATABASE_URL_APP"), { max: 5 });
}

export async function closeDb(sql: ReturnType<typeof postgres>) {
  await sql.end({ timeout: 5 });
}
