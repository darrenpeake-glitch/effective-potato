-- 0007_fix_guard_recursion.sql
-- Prevent RLS recursion by making guard functions SECURITY DEFINER and disabling row_security.

CREATE OR REPLACE FUNCTION public.require_valid_user()
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
SET row_security TO 'off'
AS $$
DECLARE
  uid uuid;
BEGIN
  uid := public.app_user_id();

  IF uid IS NULL THEN
    RAISE EXCEPTION 'app.user_id is not set' USING ERRCODE = '28000';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = uid) THEN
    RAISE EXCEPTION 'invalid app.user_id: %', uid USING ERRCODE = '28000';
  END IF;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.require_valid_org()
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
SET row_security TO 'off'
AS $$
DECLARE
  oid uuid;
BEGIN
  oid := public.app_org_id();

  IF oid IS NULL THEN
    RAISE EXCEPTION 'app.org_id is not set' USING ERRCODE = '28000';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.orgs o WHERE o.id = oid) THEN
    RAISE EXCEPTION 'invalid app.org_id: %', oid USING ERRCODE = '28000';
  END IF;

  RETURN true;
END;
$$;
