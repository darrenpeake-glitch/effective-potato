import type { Config } from "drizzle-kit";

export default {
  schema: "./src/db/schema.ts",
  out: "./src/db/migrations",
  dialect: "postgresql",
  dbCredentials: {
    // IMPORTANT: migrations must run with a privileged URL (owner/admin)
    url: process.env.DATABASE_URL_MIGRATE!,
  },
  // Store Drizzle migration bookkeeping in PUBLIC, not in schema "drizzle".
  // This avoids "permission denied for schema drizzle" and schema ownership issues.
  migrations: {
    schema: "public",
    table: "__drizzle_migrations",
  },
} satisfies Config;
