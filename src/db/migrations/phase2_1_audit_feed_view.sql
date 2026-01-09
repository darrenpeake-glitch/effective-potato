-- Phase 2.1: Audit feed view
-- Purpose:
--   Stable, query-friendly "feed" projection over audit_log with actor details.
-- Safety:
--   - VIEW is SECURITY INVOKER (default): audit_log RLS continues to govern visibility.
--   - Read-only surface; app gets SELECT only.

BEGIN;

CREATE OR REPLACE VIEW public.audit_feed AS
SELECT
  al.id,
  al.org_id,
  al.created_at,
  al.action,
  al.entity,
  al.entity_id,
  al.meta,
  al.actor_user_id,
  u.email AS actor_email,
  u.name  AS actor_name
FROM public.audit_log al
LEFT JOIN public.users u
  ON u.id = al.actor_user_id;

COMMENT ON VIEW public.audit_feed IS
'Phase 2.1 audit feed projection (audit_log + users). SECURITY INVOKER; audit_log RLS governs visibility.';

DO $$
BEGIN
  -- Grant SELECT to whichever app role exists in this environment.
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
    GRANT SELECT ON public.audit_feed TO app_user;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'occono_app') THEN
    GRANT SELECT ON public.audit_feed TO occono_app;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'occono_migrate') THEN
    GRANT SELECT ON public.audit_feed TO occono_migrate;
  END IF;
END$$;

COMMIT;
