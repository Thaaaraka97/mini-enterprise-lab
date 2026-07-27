## Why users exist in both Entra ID and AD DS

Currently both environments are isolated — users are created
separately in each. This is intentional for Phase 1 and 2
to demonstrate each identity plane independently.

In a production environment this would be solved with
Microsoft Entra Connect (Phase 4), which syncs AD DS
identities to Entra ID automatically — eliminating the
need to manage users in two places.

The current dual-creation approach intentionally
demonstrates the problem that hybrid identity solves.