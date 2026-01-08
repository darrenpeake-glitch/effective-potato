import type { Config } from "drizzle-kit";

export default {
  schema: "./src/db/schema.ts",
  out: "./src/db/migrations",
  dialect: "postgresql",
  dbCredentials: {
    url: process.env.DATABASE_URL!,
  },
  // Pin provider so the tooling is aligned with Neon/Postgres usage.
  // (This does not install or use Supabase.)
  provider: "neon",
} satisfies Config;
