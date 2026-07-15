# ============================================================
# create-users.ps1
# Creates department users in Microsoft Entra ID via Graph API
# Prerequisites:
#   - PowerShell 7+
#   - Microsoft.Graph module installed
#   - lab.config.ps1 filled in at repo root
#   - Run Connect-MgGraph before executing
# Scopes needed:
#   User.ReadWrite.All, Directory.ReadWrite.All
# ============================================================

# ── Load config ───────────────────────────────────────────────
. "$PSScriptRoot/../../lab.config.ps1"

# ── Department user definitions ───────────────────────────────
$users = @(
    @{ GivenName="Alex";   Surname="Morgan"; Department="IT";      JobTitle="IT Admin";          Username="alex.morgan" }
    @{ GivenName="Jordan"; Surname="Blake";  Department="IT";      JobTitle="IT Support";        Username="jordan.blake" }
    @{ GivenName="Taylor"; Surname="Reed";   Department="HR";      JobTitle="HR Manager";        Username="taylor.reed" }
    @{ GivenName="Morgan"; Surname="Ellis";  Department="HR";      JobTitle="HR Coordinator";    Username="morgan.ellis" }
    @{ GivenName="Casey";  Surname="Quinn";  Department="HR";      JobTitle="HR Analyst";        Username="casey.quinn" }
    @{ GivenName="Riley";  Surname="Grant";  Department="Finance"; JobTitle="Finance Manager";   Username="riley.grant" }
    @{ GivenName="Avery";  Surname="Stone";  Department="Finance"; JobTitle="Financial Analyst"; Username="avery.stone" }
    @{ GivenName="Drew";   Surname="Hale";   Department="Finance"; JobTitle="Accountant";        Username="drew.hale" }
)

$createdCount = 0
$skippedCount = 0

Write-Host "`n Starting user creation against: $TenantDomain`n" -ForegroundColor Cyan

foreach ($u in $users) {
    $upn = "$($u.Username)@$TenantDomain"

    # ── Idempotency check ─────────────────────────────────────
    $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  SKIP   $upn (already exists)" -ForegroundColor Yellow
        $skippedCount++
        continue
    }

    # ── Build body hashtable ──────────────────────────────────
    $body = @{
        givenName         = $u.GivenName
        surname           = $u.Surname
        displayName       = "$($u.GivenName) $($u.Surname)"
        userPrincipalName = $upn
        mailNickname      = $u.Username
        department        = $u.Department
        jobTitle          = $u.JobTitle
        usageLocation     = $UsageLocation
        accountEnabled    = $true
        passwordProfile   = @{
            password                      = $DefaultPassword
            forceChangePasswordNextSignIn = $true
        }
    }

    New-MgUser -BodyParameter $body | Out-Null

    Write-Host "  CREATE $upn [$($u.Department)]" -ForegroundColor Green
    $createdCount++
}

Write-Host "`n Done. Created: $createdCount  |  Skipped: $skippedCount`n" -ForegroundColor Cyan

# ── Verify ────────────────────────────────────────────────────
Write-Host " Verifying — all users in tenant:`n" -ForegroundColor Cyan
Get-MgUser -All | Select-Object DisplayName, UserPrincipalName, Department |
    Sort-Object Department | Format-Table -AutoSize