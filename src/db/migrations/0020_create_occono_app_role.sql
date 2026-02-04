BEGIN;

-- Create a minimal occono_app role to ensure grants in migrations are safe to execute
-- This role is NOLOGIN by default (suitable for CI/migrations). Local dev can create
-- a LOGIN role with a password if they want to connect as this role when testing.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'occono_app') THEN
    CREATE ROLE occono_app NOLOGIN;
  END IF;
END$$;

COMMIT;
