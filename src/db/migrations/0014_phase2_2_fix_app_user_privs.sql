-- 0014_phase2_2_fix_app_user_privs.sql
-- Purpose: ensure app role has base privileges required for RLS + guard functions to work.
-- RLS remains the actual tenant/security boundary; these GRANTs are required plumbing.

BEGIN;

-- Schema usage
GRANT USAGE ON SCHEMA public TO "app_user";

-- Table privileges (minimum required by tests and repos)
GRANT SELECT ON public.orgs        TO "app_user";
GRANT SELECT ON public.memberships TO "app_user";
GRANT SELECT ON public.audit_log   TO "app_user";
GRANT SELECT ON public.users       TO "app_user";

-- Sites are APP-writable under RLS policies
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sites TO "app_user";

-- View privilege (in case earlier migration ran before role grants)
GRANT SELECT ON public.audit_feed TO "app_user";

-- Helper function EXECUTE privileges (policies/guards call these)
GRANT EXECUTE ON FUNCTION public.app_user_id() TO "app_user";
GRANT EXECUTE ON FUNCTION public.app_org_id()  TO "app_user";
GRANT EXECUTE ON FUNCTION public.is_org_member(uuid) TO "app_user";

-- These exist in your later migrations (gate + require_valid_*). Grant if present.
DO 8684
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='has_app_context'
  ) THEN
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.has_app_context() TO %I;', 'app_user');
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='require_valid_user'
  ) THEN
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.require_valid_user() TO %I;', 'app_user');
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='require_valid_org'
  ) THEN
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.require_valid_org() TO %I;', 'app_user');
  END IF;
END 8684;

COMMIT;
