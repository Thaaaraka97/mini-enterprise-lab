# Conditional Access — test results

## Environment note
Security Defaults disabled — replaced by custom CA policies.

## CA001 — Block legacy authentication
- State: Report-only
- Test: Browser sign-in as taylor.reed
- Result: Not applied (browser is modern auth — correct)
- Legacy client test: pending real legacy client

## CA002 — Require MFA for all users
- State: Report-only
- Test: Browser sign-in as taylor.reed
- Result: Report-only: User action required (correct)
- MFA not enforced in report-only mode — expected behaviour
- Admin account excluded from scope — verified

## Conclusion
Both policies evaluated correctly against sign-in logs.
Ready to enable when moving to production-like state.