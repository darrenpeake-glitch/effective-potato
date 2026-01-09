import postgres, { type Sql } from "postgres";

function mustEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env var: ${name}`);
  return v;
}

// ADMIN: max:1 is fine (server ops are transactional)
export function adminDb(): Sql {
  return postgres(mustEnv("DATABASE_URL_ADMIN"), { max: 1 });
}

// APP: request-scoped; transactions pin a connection
export function appDb(): Sql {
  return postgres(mustEnv("DATABASE_URL_APP"), { max: 5 });
}

export async function closeDb(sql: Sql) {
  await sql.end({ timeout: 5 });
}
