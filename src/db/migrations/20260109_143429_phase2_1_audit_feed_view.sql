-- Phase 2.1: Audit feed performance + read-only view
-- Idempotent (safe to re-run).

BEGIN;

-- 1) Indexes for feed queries
-- Primary feed: latest events in org
CREATE INDEX IF NOT EXISTS audit_log_org_created_at_id_desc_idx
  ON public.audit_log (org_id, created_at DESC, id DESC);

-- Entity drilldown: latest events for entity within org
CREATE INDEX IF NOT EXISTS audit_log_org_entity_entity_id_created_at_id_desc_idx
  ON public.audit_log (org_id, entity, entity_id, created_at DESC, id DESC);

-- 2) Read-only feed view
-- Note: RLS is enforced on the underlying table for non-owners.
-- This view is intentionally simple; filtering happens in policies via app_org_id().
CREATE OR REPLACE VIEW public.v_audit_log_feed AS
SELECT
  id,
  org_id,
  actor_user_id,
  action,
  entity,
  entity_id,
  created_at,
  meta
FROM public.audit_log
ORDER BY created_at DESC, id DESC;

-- 3) Privileges: app role should be able to SELECT the view (read-only surface)
-- This will not bypass table RLS.
DO $$
BEGIN
  -- If a legacy role exists, grant it too; ignore if absent.
  BEGIN
    EXECUTE 'GRANT SELECT ON public.v_audit_log_feed TO occono_app';
  EXCEPTION WHEN undefined_object THEN
    NULL;
  END;

  -- If your Phase 2 setup uses app_user, grant it as well; ignore if absent.
  BEGIN
    EXECUTE 'GRANT SELECT ON public.v_audit_log_feed TO app_user';
  EXCEPTION WHEN undefined_object THEN
    NULL;
  END;
END $$;

COMMIT;
