-- 0013_phase2_2_recreate_audit_feed_view.sql
-- Fix: Drop and recreate audit_feed to avoid CREATE OR REPLACE column-mapping conflicts.

BEGIN;

-- Drop first so Postgres does not attempt to remap existing column names/order.
DROP VIEW IF EXISTS public.audit_feed;

-- Recreate as SECURITY INVOKER so RLS applies to the caller (app_user), not the owner.
CREATE VIEW public.audit_feed
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
