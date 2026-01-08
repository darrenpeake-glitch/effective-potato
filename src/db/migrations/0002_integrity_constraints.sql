-- 0002_integrity_constraints.sql
-- Adds FK + uniqueness + check constraints for multi-tenant integrity.

-- memberships.role allowed values
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'memberships_role_check'
  ) THEN
    ALTER TABLE public.memberships
      ADD CONSTRAINT memberships_role_check
      CHECK (role IN ('owner','admin','member'));
  END IF;
END $$;

-- Prevent duplicate membership rows
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'memberships_org_user_uniq'
  ) THEN
    ALTER TABLE public.memberships
      ADD CONSTRAINT memberships_org_user_uniq
      UNIQUE (org_id, user_id);
  END IF;
END $$;

-- Prevent duplicate site names within an org
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'sites_org_name_uniq'
  ) THEN
    ALTER TABLE public.sites
      ADD CONSTRAINT sites_org_name_uniq
      UNIQUE (org_id, name);
  END IF;
END $$;

-- Foreign keys (idempotent add pattern)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'sites_org_id_fkey'
  ) THEN
    ALTER TABLE public.sites
      ADD CONSTRAINT sites_org_id_fkey
      FOREIGN KEY (org_id) REFERENCES public.orgs(id)
      ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'memberships_org_id_fkey'
  ) THEN
    ALTER TABLE public.memberships
      ADD CONSTRAINT memberships_org_id_fkey
      FOREIGN KEY (org_id) REFERENCES public.orgs(id)
      ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'memberships_user_id_fkey'
  ) THEN
    ALTER TABLE public.memberships
      ADD CONSTRAINT memberships_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES public.users(id)
      ON DELETE CASCADE;
  END IF;
END $$;
