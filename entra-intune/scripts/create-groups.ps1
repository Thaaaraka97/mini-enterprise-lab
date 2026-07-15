# ============================================================
# create-groups.ps1
# Creates security groups and assigns members in Entra ID
# Prerequisites:
#   - PowerShell 7+
#   - Microsoft.Graph module installed
#   - lab.config.ps1 filled in at repo root
#   - Run Connect-MgGraph before executing
# Scopes needed:
#   Group.ReadWrite.All, User.Read.All
# ============================================================

# ── Load config ───────────────────────────────────────────────
. "$PSScriptRoot/../../lab.config.ps1"

# ── Group definitions ─────────────────────────────────────────
# import csv file
$groups = Import-Csv -Path "$PSScriptRoot/groups.csv"

$createdCount = 0
$skippedCount = 0

Write-Host "`n Starting group creation against: $TenantDomain`n" -ForegroundColor Cyan

foreach ($g in $groups) {

    # ── Idempotency check ─────────────────────────────────────
    $existing = Get-MgGroup -Filter "displayName eq '$($g.DisplayName)'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  SKIP   $($g.DisplayName) (already exists)" -ForegroundColor Yellow
        $skippedCount++
        continue
    }

    # ── Create group ──────────────────────────────────────────
    $newGroup = New-MgGroup -BodyParameter @{
        displayName     = $g.DisplayName
        description     = $g.Description
        mailEnabled     = $false
        mailNickname    = $g.DisplayName.ToLower()
        securityEnabled = $true
    }

    Write-Host "  CREATE $($g.DisplayName)" -ForegroundColor Green
    $createdCount++

    # ── Find and add department members ───────────────────────
    $members = Get-MgUser -Filter "department eq '$($g.Department)'" -All
    $addedCount = 0

    foreach ($member in $members) {
        New-MgGroupMember -GroupId $newGroup.Id -BodyParameter @{
            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($member.Id)"
        }
        Write-Host "    + $($member.DisplayName) → $($g.DisplayName)" -ForegroundColor DarkGreen
        $addedCount++
    }

    Write-Host "    Members added: $addedCount`n" -ForegroundColor DarkGreen
}

Write-Host " Done. Created: $createdCount  |  Skipped: $skippedCount`n" -ForegroundColor Cyan

# ── Verify ────────────────────────────────────────────────────
Write-Host " Verifying — all groups:`n" -ForegroundColor Cyan
Get-MgGroup -All | Where-Object { $_.DisplayName -like "GRP-*" } |
    Select-Object DisplayName, Description, SecurityEnabled |
    Format-Table -AutoSize