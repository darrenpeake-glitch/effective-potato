-- Audit log hardening: append-only + tenant scoped reads.
-- Assumes:
-- - public.audit_log exists with at least: id, org_id, created_at, action, actor_user_id, meta (or similar)
-- - helper functions exist: app_user_id(), app_org_id(), is_org_member(uuid)

BEGIN;

-- Ensure RLS is on (should already be true, but safe).
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log FORCE ROW LEVEL SECURITY;

-- Remove any existing policies to avoid drift.
DO $$
DECLARE
  pol record;
BEGIN
  FOR pol IN
    SELECT polname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'audit_log'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.audit_log;', pol.polname);
  END LOOP;
END$$;

-- Privileges: APP can SELECT only, cannot write.
REVOKE INSERT, UPDATE, DELETE ON public.audit_log FROM occono_app;
GRANT  SELECT ON public.audit_log TO occono_app;

-- Migrate/admin keeps full control.
GRANT INSERT, UPDATE, DELETE, SELECT ON public.audit_log TO occono_migrate;

-- SELECT: only within active org context and membership
CREATE POLICY audit_log_select
ON public.audit_log
FOR SELECT
TO occono_app
USING (
  app_org_id() IS NOT NULL
  AND app_user_id() IS NOT NULL
  AND org_id = app_org_id()
  AND is_org_member(org_id)
);

-- Explicitly deny writes (defense-in-depth even though GRANTs already block).
CREATE POLICY audit_log_insert
ON public.audit_log
FOR INSERT
TO occono_app
WITH CHECK (false);

CREATE POLICY audit_log_update
ON public.audit_log
FOR UPDATE
TO occono_app
USING (false)
WITH CHECK (false);

CREATE POLICY audit_log_delete
ON public.audit_log
FOR DELETE
TO occono_app
USING (false);

COMMIT;
