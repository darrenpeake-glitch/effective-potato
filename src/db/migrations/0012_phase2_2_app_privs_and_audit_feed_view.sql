-- 0012_phase2_2_app_privs_and_audit_feed_view.sql
-- Purpose:
--   1) Ensure the *actual* app role used in tests (app_user) has required privileges.
--   2) Ensure audit_feed does not bypass RLS by running as view owner.
--
-- Assumptions:
--   - Core tables exist: public.orgs, public.sites, public.memberships, public.audit_log, public.users
--   - RLS helper functions exist in public: app_user_id(), app_org_id(), is_org_member(uuid),
--     has_app_context(), require_valid_user(), require_valid_org()
--   - Postgres version supports SECURITY INVOKER views (PG15+; Neon typically does)

BEGIN;

-- -----------------------------
-- 1) App role privileges
-- -----------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
    RAISE EXCEPTION 'app role "%" does not exist', 'app_user';
  END IF;
END
$$;

-- Schema usage
GRANT USAGE ON SCHEMA public TO "app_user";

-- Table privileges (RLS still applies)
-- Orgs: read-only
GRANT SELECT ON public.orgs TO "app_user";
REVOKE INSERT, UPDATE, DELETE ON public.orgs FROM "app_user";

-- Memberships: read-only (per policy)
GRANT SELECT ON public.memberships TO "app_user";
REVOKE INSERT, UPDATE, DELETE ON public.memberships FROM "app_user";

-- Sites: read/write under RLS policies
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sites TO "app_user";

-- Audit_log: SELECT only (append-only server writes)
GRANT SELECT ON public.audit_log TO "app_user";
REVOKE INSERT, UPDATE, DELETE ON public.audit_log FROM "app_user";

-- Users: read-only (used for joining actor info in views)
GRANT SELECT ON public.users TO "app_user";

-- Function EXECUTE privileges (RLS policies call these)
GRANT EXECUTE ON FUNCTION public.app_user_id() TO "app_user";
GRANT EXECUTE ON FUNCTION public.app_org_id() TO "app_user";
GRANT EXECUTE ON FUNCTION public.is_org_member(uuid) TO "app_user";

-- These exist in your current policy set (seen in output)
GRANT EXECUTE ON FUNCTION public.has_app_context() TO "app_user";
GRANT EXECUTE ON FUNCTION public.require_valid_user() TO "app_user";
GRANT EXECUTE ON FUNCTION public.require_valid_org() TO "app_user";

-- Older/alternate guard function names may exist in repo history; grant if present.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
             WHERE n.nspname='public' AND p.proname='assert_valid_user') THEN
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.assert_valid_user() TO %I', 'app_user');
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
             WHERE n.nspname='public' AND p.proname='assert_valid_org') THEN
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.assert_valid_org() TO %I', 'app_user');
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
             WHERE n.nspname='public' AND p.proname='require_valid_user') THEN
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.require_valid_user() TO %I', 'app_user');
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
             WHERE n.nspname='public' AND p.proname='require_valid_org') THEN
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.require_valid_org() TO %I', 'app_user');
  END IF;
END
$$;

-- -----------------------------
-- 2) Recreate audit_feed as SECURITY INVOKER (prevents RLS bypass)
-- -----------------------------
-- Notes:
-- - Without SECURITY INVOKER, a view typically runs with view-owner privileges, which can bypass RLS.
-- - We return meta as jsonb (not text) to keep it structured.
CREATE OR REPLACE VIEW public.audit_feed
WITH (security_invoker = true)
AS
SELECT
  a.id,
  a.org_id,
  a.actor_user_id,
  u.name  AS actor_name,
  u.email AS actor_email,
  a.action,
  a.entity,
  a.entity_id,
  a.meta,
  a.created_at
FROM public.audit_log a
LEFT JOIN public.users u ON u.id = a.actor_user_id;

GRANT SELECT ON public.audit_feed TO "app_user";

COMMIT;
