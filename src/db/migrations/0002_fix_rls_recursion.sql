-- Fix RLS recursion by making membership check SECURITY DEFINER (bypass RLS as table owner)
-- and simplify memberships SELECT policy to avoid self-referential membership checks.

SET search_path TO public;

-- Replace helper with SECURITY DEFINER; set safe search_path to prevent hijacking.
CREATE OR REPLACE FUNCTION public.is_org_member(target_org_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.memberships m
    WHERE m.org_id = target_org_id
      AND m.user_id = public.app_user_id()
  );
$$;

-- Lock down EXECUTE (good hygiene)
REVOKE ALL ON FUNCTION public.is_org_member(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_org_member(uuid) TO occono_app;

-- Recreate memberships SELECT policy to avoid recursion.
DROP POLICY IF EXISTS memberships_select ON public.memberships;
CREATE POLICY memberships_select ON public.memberships
FOR SELECT
USING (
  public.app_org_id() IS NOT NULL
  AND public.app_user_id() IS NOT NULL
  AND org_id = public.app_org_id()
  AND user_id = public.app_user_id()
);
