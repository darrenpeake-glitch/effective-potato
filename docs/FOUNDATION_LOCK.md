# Foundation Lock

As of this commit:
- Core schema is finalised
- RLS is fail-closed and tenant-safe
- Auth context is enforced via app.user_id / app.org_id
- All database access paths are regression-tested

No feature work should modify:
- RLS policies
- Auth context functions
- Core tables (orgs, sites, memberships, users)
without adding or updating tests first.
