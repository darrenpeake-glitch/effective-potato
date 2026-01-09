-- Phase 2.1: Audit feed performance + read-only view
-- Idempotent.

BEGIN;

-- Indexes for feed queries
CREATE INDEX IF NOT EXISTS audit_log_org_created_at_id_desc_idx
  ON public.audit_log (org_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS audit_log_org_entity_entity_id_created_at_id_desc_idx
  ON public.audit_log (org_id, entity, entity_id, created_at DESC, id DESC);

-- Read-only feed view (RLS still enforced on underlying table)
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

-- Grant SELECT on the view to known app roles if present (ignore if absent)
DO $$
BEGIN
  BEGIN
    EXECUTE 'GRANT SELECT ON public.v_audit_log_feed TO occono_app';
  EXCEPTION WHEN undefined_object THEN
    NULL;
  END;

  BEGIN
    EXECUTE 'GRANT SELECT ON public.v_audit_log_feed TO app_user';
  EXCEPTION WHEN undefined_object THEN
    NULL;
  END;
END $$;

COMMIT;
