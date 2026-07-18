# ============================================================
# assign-roles.ps1
# Assigns Entra ID RBAC roles to specific users
# Prerequisites:
#   - PowerShell 7+
#   - Microsoft.Graph module installed
#   - lab.config.ps1 filled in at repo root
#   - Run Connect-MgGraph before executing
# Scopes needed:
#   RoleManagement.ReadWrite.Directory, User.Read.All
# ============================================================

. "$PSScriptRoot/../../lab.config.ps1"

# ── Role assignments to make ──────────────────────────────────
# import csv file
$roleAssignments = Import-Csv -Path "$PSScriptRoot/roles.csv"

$assignedCount = 0
$skippedCount  = 0

Write-Host "`n Starting role assignments against: $TenantDomain`n" -ForegroundColor Cyan

foreach ($assignment in $roleAssignments) {
    $upn  = "$($assignment.Username)@$TenantDomain"

    # ── Get user ──────────────────────────────────────────────
    $user = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
    if (-not $user) {
        Write-Host "  ERROR  User not found: $upn" -ForegroundColor Red
        continue
    }

    # ── Get role definition ───────────────────────────────────
    $role = Get-MgRoleManagementDirectoryRoleDefinition `
        -Filter "displayName eq '$($assignment.RoleName)'" `
        -ErrorAction SilentlyContinue
    if (-not $role) {
        Write-Host "  ERROR  Role not found: $($assignment.RoleName)" -ForegroundColor Red
        continue
    }

    # ── Idempotency — check if already assigned ───────────────
    $existing = Get-MgRoleManagementDirectoryRoleAssignment `
        -Filter "principalId eq '$($user.Id)' and roleDefinitionId eq '$($role.Id)'" `
        -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  SKIP   $upn → $($assignment.RoleName) (already assigned)" -ForegroundColor Yellow
        $skippedCount++
        continue
    }

    # ── Assign role ───────────────────────────────────────────
    New-MgRoleManagementDirectoryRoleAssignment -BodyParameter @{
        principalId      = $user.Id
        roleDefinitionId = $role.Id
        directoryScopeId = "/"        # "/" = tenant-wide scope
    } | Out-Null

    Write-Host "  ASSIGN $upn → $($assignment.RoleName)" -ForegroundColor Green
    $assignedCount++
}

Write-Host "`n Done. Assigned: $assignedCount  |  Skipped: $skippedCount`n" -ForegroundColor Cyan

# ── Verify ────────────────────────────────────────────────────
Write-Host " Verifying role assignments:`n" -ForegroundColor Cyan
foreach ($assignment in $roleAssignments) {
    $upn  = "$($assignment.Username)@$TenantDomain"
    $user = Get-MgUser -Filter "userPrincipalName eq '$upn'"
    $assignments = Get-MgRoleManagementDirectoryRoleAssignment `
        -Filter "principalId eq '$($user.Id)'"
    foreach ($a in $assignments) {
        $roleDef = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $a.RoleDefinitionId
        Write-Host "  $upn → $($roleDef.DisplayName)" -ForegroundColor Green
    }
}