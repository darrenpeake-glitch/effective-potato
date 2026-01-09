-- 0015_phase2_2_fix_app_privs_all.sql
-- Purpose:
--   Ensure the role used by the application/tests has BASE privileges.
--   RLS remains the tenant boundary; these are required for queries to run at all.
--
-- Strategy:
--   - Apply grants to app_user and (if it exists) occono_app.
--   - Grant across ALL TABLES / ALL FUNCTIONS in public schema to avoid missing objects/signatures.
--   - Add default privileges so future objects don't regress.

BEGIN;

DO $$
DECLARE
  r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['app_user', 'occono_app']
  LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      -- Schema access
      EXECUTE format('GRANT USAGE ON SCHEMA public TO %I;', r);

      -- Tables: allow the app role to run SELECT/INSERT/UPDATE/DELETE, with RLS enforcing tenant rules.
      EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO %I;', r);

      -- Sequences (needed if any table uses serial/identity + nextval)
      EXECUTE format('GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO %I;', r);

      -- Functions: policies/guards often call helper functions; grant EXECUTE broadly.
      EXECUTE format('GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO %I;', r);

      -- Default privileges for future objects created in public schema.
      -- Note: these apply to objects created by the current owner role executing this migration.
      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I;', r);
      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO %I;', r);
      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO %I;', r);
    END IF;
  END LOOP;
END
$$;

COMMIT;
