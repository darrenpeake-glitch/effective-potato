-- 0008_context_presence_gate.sql
-- Gate guard execution so missing app context fails closed (no rows) rather than raising.

CREATE OR REPLACE FUNCTION public.has_app_context()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT public.app_user_id() IS NOT NULL
     AND public.app_org_id()  IS NOT NULL;
$$;
