# ============================================================
# add-group-members.ps1
# Assigns members according to the department in Entra ID
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
$groups = Get-MgGroup -All -Property "ID,DisplayName"

$addedCount = 0
$skippedCount = 0

foreach ($group in $groups){
    # ── Filter the department name from the group ───────────────────────
    $group_department = $group.DisplayName.Substring(4)

    # ── Find and add department members ───────────────────────
    $members = Get-MgUser -All -Property "ID,DisplayName,Department" | Where-Object {$_.Department -eq $group_department}

    foreach ($member in $members) {
        $existing_ids = (Get-MgGroupMember -GroupId $group.Id).Id
        if ($existing_ids -contains $member.Id) {
            Write-Host "  SKIP $($member.DisplayName) (already a member)" -ForegroundColor Yellow
            $skippedCount++
            continue
        }
       
        New-MgGroupMember -GroupId $group.Id -BodyParameter @{
            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($member.Id)"
        }
        Write-Host "    + $($member.DisplayName) → $($group.DisplayName)" -ForegroundColor DarkGreen
        $addedCount++
        
      
    }
}
Write-Host "    Added: $addedCount  |  Skipped: $skippedCount" -ForegroundColor DarkGreen

# ── Verify ────────────────────────────────────────────────────
Write-Host "  Verifying group memberships:`n" -ForegroundColor Cyan
foreach ($group in $groups) {
    $memberList = Get-MgGroupMember -GroupId $group.Id -All
    Write-Host "  $($group.DisplayName) ($($memberList.Count) members)" -ForegroundColor Green
    foreach ($m in $memberList) {
        $u = Get-MgUser -UserId $m.Id -Property "DisplayName,Department"
        Write-Host "    - $($u.DisplayName) [$($u.Department)]" -ForegroundColor DarkGreen
    }
}