-- 0003_auth_context_guards.sql
-- Enforce that request context variables map to real users/orgs.

CREATE OR REPLACE FUNCTION public.assert_valid_user()
RETURNS void
LANGUAGE plpgsql
STABLE
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
END;
$$;

CREATE OR REPLACE FUNCTION public.assert_valid_org()
RETURNS void
LANGUAGE plpgsql
STABLE
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
END;
$$;
