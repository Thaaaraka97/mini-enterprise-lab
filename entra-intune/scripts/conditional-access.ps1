# ============================================================
# conditional-access.ps1
# Creates Conditional Access policies in Microsoft Entra ID
# Prerequisites:
#   - PowerShell 7+
#   - Microsoft.Graph module installed
#   - lab.config.ps1 filled in at repo root
#   - Entra ID P1/P2 licence active
#   - Run Connect-MgGraph before executing
# Scopes needed:
#   Policy.ReadWrite.ConditionalAccess, Policy.Read.All
# ============================================================

# ── Load config ───────────────────────────────────────────────
. "$PSScriptRoot/../../lab.config.ps1"

Write-Host "`n Starting Conditional Access policy creation`n" -ForegroundColor Cyan

# ── Resolve admin account to Object ID ───────────────────────
# Graph API requires GUIDs in policy bodies, not UPNs
$adminUser = Get-MgUser -Filter "userPrincipalName eq '$AdminUPN'"
if (-not $adminUser) {
    Write-Host "  ERROR  Admin user not found: $AdminUPN" -ForegroundColor Red
    Write-Host "         Check AdminUPN value in lab.config.ps1" -ForegroundColor Red
    exit 1
}
$adminId = $adminUser.Id
Write-Host "  INFO   Admin resolved → $AdminUPN ($adminId)`n" -ForegroundColor DarkCyan


# ══════════════════════════════════════════════════════════════
# POLICY 1 — Block legacy authentication
# Legacy auth bypasses MFA entirely — blocking it is
# the single highest-impact security control you can enable
# ══════════════════════════════════════════════════════════════

$policy1Name = "CA001-Block-Legacy-Authentication"

$existing1 = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$policy1Name'" -ErrorAction SilentlyContinue
if ($existing1) {
    Write-Host "  SKIP   $policy1Name (already exists)" -ForegroundColor Yellow
} else {
    $policy1 = @{
        displayName = $policy1Name
        state       = "enabledForReportingButNotEnforced"  # Report-only — safe to test
        conditions  = @{
            users = @{
                includeUsers = @("All")
            }
            applications = @{
                includeApplications = @("All")
            }
            clientAppTypes = @(
                "exchangeActiveSync",
                "other"
            )
        }
        grantControls = @{
            operator        = "OR"
            builtInControls = @("block")
        }
    }

    New-MgIdentityConditionalAccessPolicy -BodyParameter $policy1 | Out-Null
    Write-Host "  CREATE $policy1Name" -ForegroundColor Green
}

# ══════════════════════════════════════════════════════════════
# POLICY 2 — Require MFA for all users
# Enforces MFA on every sign-in across all cloud apps
# ══════════════════════════════════════════════════════════════

$policy2Name = "CA002-Require-MFA-All-Users"

$existing2 = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$policy2Name'" -ErrorAction SilentlyContinue
if ($existing2) {
    Write-Host "  SKIP   $policy2Name (already exists)" -ForegroundColor Yellow
} else {
    $policy2 = @{
        displayName = $policy2Name
        state       = "enabledForReportingButNotEnforced"  # Report-only — safe to test
        conditions  = @{
            users = @{
                includeUsers  = @("All")
                excludeUsers  = @($adminId)   # Exclude your admin — never lock yourself out
            }
            applications = @{
                includeApplications = @("All")
            }
            clientAppTypes = @("browser", "mobileAppsAndDesktopClients")
        }
        grantControls = @{
            operator        = "OR"
            builtInControls = @("mfa")
        }
    }

    New-MgIdentityConditionalAccessPolicy -BodyParameter $policy2 | Out-Null
    Write-Host "  CREATE $policy2Name" -ForegroundColor Green
}

# ── Verify ────────────────────────────────────────────────────
Write-Host "`n Verifying — all Conditional Access policies:`n" -ForegroundColor Cyan
Get-MgIdentityConditionalAccessPolicy -All |
    Select-Object DisplayName, State |
    Format-Table -AutoSize