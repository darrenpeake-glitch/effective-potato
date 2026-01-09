-- 0004_rls_require_valid_context.sql
-- Require app context to map to real rows (user + org exist).

-- ORGS: select only (no writes)
DROP POLICY IF EXISTS orgs_select ON public.orgs;
CREATE POLICY orgs_select
ON public.orgs
FOR SELECT
USING (
  public.assert_valid_user() IS NULL
  AND public.assert_valid_org() IS NULL
  AND id = public.app_org_id()
  AND public.is_org_member(id)
);

-- SITES: tenant scoping + membership
DROP POLICY IF EXISTS sites_select ON public.sites;
CREATE POLICY sites_select
ON public.sites
FOR SELECT
USING (
  public.assert_valid_user() IS NULL
  AND public.assert_valid_org() IS NULL
  AND org_id = public.app_org_id()
  AND public.is_org_member(org_id)
);

DROP POLICY IF EXISTS sites_insert ON public.sites;
CREATE POLICY sites_insert
ON public.sites
FOR INSERT
WITH CHECK (
  public.assert_valid_user() IS NULL
  AND public.assert_valid_org() IS NULL
  AND org_id = public.app_org_id()
  AND public.is_org_member(org_id)
);

DROP POLICY IF EXISTS sites_update ON public.sites;
CREATE POLICY sites_update
ON public.sites
FOR UPDATE
USING (
  public.assert_valid_user() IS NULL
  AND public.assert_valid_org() IS NULL
  AND org_id = public.app_org_id()
  AND public.is_org_member(org_id)
)
WITH CHECK (
  public.assert_valid_user() IS NULL
  AND public.assert_valid_org() IS NULL
  AND org_id = public.app_org_id()
  AND public.is_org_member(org_id)
);

DROP POLICY IF EXISTS sites_delete ON public.sites;
CREATE POLICY sites_delete
ON public.sites
FOR DELETE
USING (
  public.assert_valid_user() IS NULL
  AND public.assert_valid_org() IS NULL
  AND org_id = public.app_org_id()
  AND public.is_org_member(org_id)
);

-- MEMBERSHIPS: select only for current user in current org
DROP POLICY IF EXISTS memberships_select ON public.memberships;
CREATE POLICY memberships_select
ON public.memberships
FOR SELECT
USING (
  public.assert_valid_user() IS NULL
  AND public.assert_valid_org() IS NULL
  AND org_id = public.app_org_id()
  AND user_id = public.app_user_id()
);

-- AUDIT_LOG: select only for tenant
DROP POLICY IF EXISTS audit_log_select ON public.audit_log;
CREATE POLICY audit_log_select
ON public.audit_log
FOR SELECT
USING (
  public.assert_valid_user() IS NULL
  AND public.assert_valid_org() IS NULL
  AND org_id = public.app_org_id()
  AND public.is_org_member(org_id)
);
