-- Repair: stop RLS recursion by:
-- 1) making is_org_member SECURITY DEFINER + row_security=off
-- 2) making memberships_select non-recursive (no is_org_member call)

SET search_path TO public;

-- (1) Replace helper
CREATE OR REPLACE FUNCTION public.is_org_member(target_org_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
SET row_security = off
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.memberships m
    WHERE m.org_id = target_org_id
      AND m.user_id = public.app_user_id()
  );
$$;

REVOKE ALL ON FUNCTION public.is_org_member(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_org_member(uuid) TO occono_app;

-- (2) Replace memberships SELECT policy to avoid recursion
DROP POLICY IF EXISTS memberships_select ON public.memberships;

CREATE POLICY memberships_select ON public.memberships
FOR SELECT
USING (
  public.app_org_id() IS NOT NULL
  AND public.app_user_id() IS NOT NULL
  AND org_id = public.app_org_id()
  AND user_id = public.app_user_id()
);
