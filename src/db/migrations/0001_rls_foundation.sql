-- RLS foundation for Occono Auto (fail-closed)
-- Strategy:
-- - The app sets Postgres session vars:
--     set_config('app.user_id', '<uuid>', true)
--     set_config('app.org_id',  '<uuid>', true)
-- - If either is missing/invalid, policies evaluate to FALSE (deny).
-- - Membership is validated against memberships(org_id, user_id).

-- Ensure we are operating in public
SET search_path TO public;

-- Helper: safely read session UUIDs; returns NULL when missing/invalid.
CREATE OR REPLACE FUNCTION public.app_user_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
AS $$
DECLARE v text;
BEGIN
  v := current_setting('app.user_id', true);
  IF v IS NULL OR v = '' THEN
    RETURN NULL;
  END IF;
  RETURN v::uuid;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_org_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
AS $$
DECLARE v text;
BEGIN
  v := current_setting('app.org_id', true);
  IF v IS NULL OR v = '' THEN
    RETURN NULL;
  END IF;
  RETURN v::uuid;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;

-- Helper: membership check (fail-closed)
CREATE OR REPLACE FUNCTION public.is_org_member(target_org_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.memberships m
    WHERE m.org_id = target_org_id
      AND m.user_id = public.app_user_id()
  );
$$;

-- Enable RLS on tenant-scoped tables
ALTER TABLE public.orgs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- Optional: keep owners/admins logic for later; for now membership gates access.
-- Policies: ORGS
DROP POLICY IF EXISTS orgs_select ON public.orgs;
CREATE POLICY orgs_select ON public.orgs
FOR SELECT
USING (
  public.app_org_id() IS NOT NULL
  AND id = public.app_org_id()
  AND public.is_org_member(id)
);

DROP POLICY IF EXISTS orgs_insert ON public.orgs;
CREATE POLICY orgs_insert ON public.orgs
FOR INSERT
WITH CHECK (false);

DROP POLICY IF EXISTS orgs_update ON public.orgs;
CREATE POLICY orgs_update ON public.orgs
FOR UPDATE
USING (false)
WITH CHECK (false);

DROP POLICY IF EXISTS orgs_delete ON public.orgs;
CREATE POLICY orgs_delete ON public.orgs
FOR DELETE
USING (false);

-- Policies: SITES (scoped by org_id)
DROP POLICY IF EXISTS sites_select ON public.sites;
CREATE POLICY sites_select ON public.sites
FOR SELECT
USING (
  public.app_org_id() IS NOT NULL
  AND org_id = public.app_org_id()
  AND public.is_org_member(org_id)
);

DROP POLICY IF EXISTS sites_insert ON public.sites;
CREATE POLICY sites_insert ON public.sites
FOR INSERT
WITH CHECK (
  public.app_org_id() IS NOT NULL
  AND org_id = public.app_org_id()
  AND public.is_org_member(org_id)
);

DROP POLICY IF EXISTS sites_update ON public.sites;
CREATE POLICY sites_update ON public.sites
FOR UPDATE
USING (
  public.app_org_id() IS NOT NULL
  AND org_id = public.app_org_id()
  AND public.is_org_member(org_id)
)
WITH CHECK (
  public.app_org_id() IS NOT NULL
  AND org_id = public.app_org_id()
  AND public.is_org_member(org_id)
);

DROP POLICY IF EXISTS sites_delete ON public.sites;
CREATE POLICY sites_delete ON public.sites
FOR DELETE
USING (
  public.app_org_id() IS NOT NULL
  AND org_id = public.app_org_id()
  AND public.is_org_member(org_id)
);

-- Policies: MEMBERSHIPS
-- Read membership rows only for your current org (and only if you are a member).
DROP POLICY IF EXISTS memberships_select ON public.memberships;
CREATE POLICY memberships_select ON public.memberships
FOR SELECT
USING (
  public.app_org_id() IS NOT NULL
  AND org_id = public.app_org_id()
  AND public.is_org_member(org_id)
);

-- Writes to memberships are disabled for now (admin flows later)
DROP POLICY IF EXISTS memberships_insert ON public.memberships;
CREATE POLICY memberships_insert ON public.memberships
FOR INSERT
WITH CHECK (false);

DROP POLICY IF EXISTS memberships_update ON public.memberships;
CREATE POLICY memberships_update ON public.memberships
FOR UPDATE
USING (false)
WITH CHECK (false);

DROP POLICY IF EXISTS memberships_delete ON public.memberships;
CREATE POLICY memberships_delete ON public.memberships
FOR DELETE
USING (false);

-- Policies: AUDIT_LOG (append-only later; for now allow insert+select in-org)
DROP POLICY IF EXISTS audit_log_select ON public.audit_log;
CREATE POLICY audit_log_select ON public.audit_log
FOR SELECT
USING (
  public.app_org_id() IS NOT NULL
  AND org_id = public.app_org_id()
  AND public.is_org_member(org_id)
);

DROP POLICY IF EXISTS audit_log_insert ON public.audit_log;
CREATE POLICY audit_log_insert ON public.audit_log
FOR INSERT
WITH CHECK (
  public.app_org_id() IS NOT NULL
  AND org_id = public.app_org_id()
  AND public.is_org_member(org_id)
  AND actor_user_id = public.app_user_id()
);

-- Updates/deletes disabled
DROP POLICY IF EXISTS audit_log_update ON public.audit_log;
CREATE POLICY audit_log_update ON public.audit_log
FOR UPDATE
USING (false)
WITH CHECK (false);

DROP POLICY IF EXISTS audit_log_delete ON public.audit_log;
CREATE POLICY audit_log_delete ON public.audit_log
FOR DELETE
USING (false);

-- Runtime privileges for occono_app (minimal)
-- Note: RLS still applies; privileges alone do not grant cross-tenant access.
GRANT USAGE ON SCHEMA public TO occono_app;

GRANT SELECT ON public.orgs TO occono_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sites TO occono_app;
GRANT SELECT ON public.memberships TO occono_app;
GRANT SELECT, INSERT ON public.audit_log TO occono_app;

-- Users table is not tenant-scoped in this model yet; keep runtime read-only for now.
GRANT SELECT ON public.users TO occono_app;
