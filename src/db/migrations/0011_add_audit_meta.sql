BEGIN;

ALTER TABLE public.audit_log
  ADD COLUMN IF NOT EXISTS meta jsonb;

COMMIT;
