# Entra ID + Intune — architecture decisions

This document explains the design choices made in the cloud environment and the reasoning behind each one. These are the trade-offs that come up in interviews — knowing why you made a choice is more important than knowing what you built.

---

## 1. Why Entra ID P2 instead of P1

**Decision:** Activated Entra ID P2 trial instead of the free tier or P1.

**Reasoning:** P2 includes Identity Protection (risky sign-in detection) and Privileged Identity Management (just-in-time admin access). These are standard in enterprise environments handling sensitive data. P1 covers Conditional Access which is the minimum for this lab, but P2 demonstrates awareness of the full security stack.

**Trade-off:** P2 trial expires in 30 days. In production, P2 licensing is per-user and costs more than P1. Many organisations run a hybrid — P2 for admins and privileged users, P1 for standard users.

---

## 2. Why Conditional Access policies in report-only mode

**Decision:** Both CA001 and CA002 stay in `enabledForReportingButNotEnforced` state.

**Reasoning:** Enabling CA policies without verifying them first is how you lock yourself and your users out of the tenant. Report-only mode evaluates the policy logic against every real sign-in and logs the result without enforcing it. You verify the logic is correct in sign-in logs before flipping to enabled. This is standard practice in every enterprise CA rollout.

**Trade-off:** The policies provide no actual enforcement in report-only mode. A production rollout would verify in report-only for 1-2 weeks, then enable CA001 first (legacy auth block), then CA002 (MFA requirement) after MFA registration is confirmed across all users.

**Verified:** Sign-in logs confirmed CA001 shows Not applied on browser sign-ins (correct — browser is not a legacy client) and CA002 shows User action required (correct — MFA would be required if enforced).

---

## 3. Why the admin account is excluded from CA002

**Decision:** The admin account is explicitly excluded from the MFA Conditional Access policy via the `excludeUsers` property.

**Reasoning:** This is the break-glass pattern. If MFA infrastructure fails — authenticator app unavailable, phone lost, MFA service outage — a Global Admin locked behind MFA with no fallback means complete loss of tenant access. The excluded admin account is the emergency access path.

**Trade-off:** The admin account is less protected than standard users. In production this is mitigated by storing the break-glass account credentials in a physical safe, enabling audit logging on every sign-in, and using a very strong password with no MFA registered.

---

## 4. Why -BodyParameter instead of individual cmdlet parameters

**Decision:** All Microsoft Graph PowerShell cmdlets use `-BodyParameter` hashtables instead of individual named parameters.

**Reasoning:** Microsoft.Graph module v2.x introduced breaking changes where boolean parameters like `-AccountEnabled $true` and complex objects like `-PasswordProfile` stopped accepting inline values. `-BodyParameter` sends the payload directly as JSON to the Graph REST API, bypassing the PowerShell parameter binding layer entirely. It is version-agnostic and mirrors exactly what the REST API expects.

**Trade-off:** `-BodyParameter` is less readable than named parameters for someone unfamiliar with the Graph API schema. The JSON keys must match the API property names exactly (camelCase). The benefit is consistency — the same pattern works across all Graph module versions.

---

## 5. Why client-side filtering instead of server-side OData

**Decision:** `Get-MgUser -All -Property "Id,DisplayName,Department" | Where-Object { $_.Department -eq "IT" }` instead of `Get-MgUser -Filter "department eq 'IT'"`.

**Reasoning:** Only indexed properties in Entra ID support reliable server-side OData filtering. Indexed properties include `userPrincipalName`, `displayName`, `mail`, and `id`. `Department` is not indexed — server-side filtering on it silently returns empty results with no error. Client-side filtering fetches all users and filters locally, which is reliable regardless of which properties are indexed.

**Trade-off:** Client-side filtering fetches all users every time, which is inefficient at scale. In a tenant with 10,000+ users this would be slow and consume significant API quota. At lab scale (8 users) it is irrelevant. The production solution is to use indexed properties for filtering or to store department in an extension attribute that is indexed.

---

## 6. Why users and groups exist in both Entra ID and AD DS

**Decision:** The same 8 users and 3 groups are created independently in both environments.

**Reasoning:** Both environments are currently isolated — there is no identity sync between them. This is intentional for Phase 1 and 2 to demonstrate each identity plane independently. It also demonstrates the problem that hybrid identity solves — managing users in two separate stores is the pain point that Entra Connect eliminates.

**Trade-off:** Double the management overhead. In production this would never be acceptable. Phase 4 (Entra Connect) resolves this by syncing AD DS identities to Entra ID automatically — one source of truth, one password, one management plane.

---

## 7. Why sensitive values live in lab.config.ps1

**Decision:** All sensitive values — tenant domain, admin UPN, default passwords — are stored in `lab.config.ps1` which is gitignored. A safe template with empty values is committed.

**Reasoning:** Hardcoding credentials in scripts that are committed to a public GitHub repository is a critical security failure. GitHub's secret scanning would flag it, and the credentials would be permanently in the git history even if later removed. The config file pattern mirrors how production scripts handle secrets — environment variables, key vaults, or parameter files that are never committed.

**Trade-off:** Anyone cloning the repo must fill in their own `lab.config.ps1` before running scripts. The template file makes this clear. In production, secrets would live in Azure Key Vault and be injected at runtime rather than stored in a local file.

---

## 8. Why Security Defaults was disabled

**Decision:** Disabled Microsoft Entra Security Defaults before creating Conditional Access policies.

**Reasoning:** Security Defaults and Conditional Access are mutually exclusive. When Security Defaults is enabled it runs as a tenant-level policy that completely overrides all custom CA policies — they exist but are never evaluated. Custom CA policies give granular control that Security Defaults does not — per-group exclusions, named location conditions, device compliance requirements, sign-in risk integration. Disabling Security Defaults is a prerequisite for any custom CA deployment.

**Trade-off:** The period between disabling Security Defaults and enabling custom CA policies is a window with no MFA enforcement. In production this window should be minimised — disable Security Defaults and enable CA policies in the same change window, ideally outside business hours.