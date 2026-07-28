# ============================================================
# create-ou.ps1
# Creates OUs, users, groups and configures delegation
# Run as Administrator on the Domain Controller
# Prerequisites: AD DS installed and forest promoted
# ============================================================


# ── Configuration ─────────────────────────────────────────────
$DomainDN   = "DC=corp,DC=local"
$DomainName = "corp.local"
$DefaultPassword = Read-Host -Prompt "Enter default password for users" -AsSecureString

# ══════════════════════════════════════════════════════════════
# BLOCK 1 — Create OUs
# ══════════════════════════════════════════════════════════════
Write-Host "`n Creating OUs..." -ForegroundColor Cyan

$ous = @("IT", "HR", "Finance")
foreach ($ou in $ous) {
    $ouDN = "OU=$ou,$DomainDN"
    $existing = Get-ADOrganizationalUnit `
        -Filter "DistinguishedName -eq '$ouDN'" `
        -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  SKIP   OU=$ou (already exists)" -ForegroundColor Yellow
    } else {
        New-ADOrganizationalUnit `
            -Name                            $ou `
            -Path                            $DomainDN `
            -ProtectedFromAccidentalDeletion $true
        Write-Host "  CREATE OU=$ou" -ForegroundColor Green
    }
}

# ══════════════════════════════════════════════════════════════
# BLOCK 2 — Create users inside their OUs
# ══════════════════════════════════════════════════════════════
Write-Host "`n Creating users..." -ForegroundColor Cyan

$users = @(
    @{ Name="Alex Morgan";   Sam="alex.morgan";   Dept="IT";      Title="IT Admin" }
    @{ Name="Jordan Blake";  Sam="jordan.blake";  Dept="IT";      Title="IT Support" }
    @{ Name="Taylor Reed";   Sam="taylor.reed";   Dept="HR";      Title="HR Manager" }
    @{ Name="Morgan Ellis";  Sam="morgan.ellis";  Dept="HR";      Title="HR Coordinator" }
    @{ Name="Casey Quinn";   Sam="casey.quinn";   Dept="HR";      Title="HR Analyst" }
    @{ Name="Riley Grant";   Sam="riley.grant";   Dept="Finance"; Title="Finance Manager" }
    @{ Name="Avery Stone";   Sam="avery.stone";   Dept="Finance"; Title="Financial Analyst" }
    @{ Name="Drew Hale";     Sam="drew.hale";     Dept="Finance"; Title="Accountant" }
)

foreach ($u in $users) {
    $existing = Get-ADUser `
        -Filter "SamAccountName -eq '$($u.Sam)'" `
        -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  SKIP   $($u.Sam) (already exists)" -ForegroundColor Yellow
        continue
    }
    New-ADUser `
        -Name                 $u.Name `
        -SamAccountName       $u.Sam `
        -UserPrincipalName    "$($u.Sam)@$DomainName" `
        -Title                $u.Title `
        -Department           $u.Dept `
        -Path                 "OU=$($u.Dept),$DomainDN" `
        -AccountPassword      $DefaultPassword `
        -Enabled              $true `
        -ChangePasswordAtLogon $true
    Write-Host "  CREATE $($u.Sam) in OU=$($u.Dept)" -ForegroundColor Green
}

# ══════════════════════════════════════════════════════════════
# BLOCK 3 — Create security groups and assign members
# ══════════════════════════════════════════════════════════════
Write-Host "`n Creating groups and assigning members..." -ForegroundColor Cyan

$groups = @(
    @{ Name="GRP-IT";      Dept="IT";      OU="IT" }
    @{ Name="GRP-HR";      Dept="HR";      OU="HR" }
    @{ Name="GRP-Finance"; Dept="Finance"; OU="Finance" }
)

foreach ($g in $groups) {
    $existing = Get-ADGroup `
        -Filter "Name -eq '$($g.Name)'" `
        -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-ADGroup `
            -Name            $g.Name `
            -SamAccountName  $g.Name `
            -GroupScope      Global `
            -GroupCategory   Security `
            -Path            "OU=$($g.OU),$DomainDN" `
            -Description     "$($g.Dept) department security group"
        Write-Host "  CREATE $($g.Name)" -ForegroundColor Green
    } else {
        Write-Host "  SKIP   $($g.Name) (already exists)" -ForegroundColor Yellow
    }

    # Add department users to group
    $deptUsers = Get-ADUser `
        -Filter "Department -eq '$($g.Dept)'" `
        -ErrorAction SilentlyContinue
    foreach ($u in $deptUsers) {
        $isMember = Get-ADGroupMember -Identity $g.Name |
            Where-Object { $_.SamAccountName -eq $u.SamAccountName }
        if (-not $isMember) {
            Add-ADGroupMember -Identity $g.Name -Members $u.SamAccountName
            Write-Host "    + $($u.SamAccountName) -> $($g.Name)" -ForegroundColor DarkGreen
        }
    }
}

# ══════════════════════════════════════════════════════════════
# BLOCK 4 — Helpdesk group and HR OU delegation
# Helpdesk can reset passwords in HR OU only
# ══════════════════════════════════════════════════════════════
Write-Host "`n Creating Helpdesk group and configuring delegation..." -ForegroundColor Cyan

$helpdeskGroup = "GRP-Helpdesk"
$itOuDN        = "OU=IT,$DomainDN"
$hrOuDN        = "OU=HR,$DomainDN"

$existing = Get-ADGroup `
    -Filter "Name -eq '$helpdeskGroup'" `
    -ErrorAction SilentlyContinue
if (-not $existing) {
    New-ADGroup `
        -Name            $helpdeskGroup `
        -SamAccountName  $helpdeskGroup `
        -GroupScope      Global `
        -GroupCategory   Security `
        -Path            $itOuDN `
        -Description     "Helpdesk staff - delegated password reset on HR OU"
    Write-Host "  CREATE $helpdeskGroup" -ForegroundColor Green
} else {
    Write-Host "  SKIP   $helpdeskGroup (already exists)" -ForegroundColor Yellow
}

# Add jordan.blake to Helpdesk group
$isMember = Get-ADGroupMember -Identity $helpdeskGroup |
    Where-Object { $_.SamAccountName -eq "jordan.blake" }
if (-not $isMember) {
    Add-ADGroupMember -Identity $helpdeskGroup -Members "jordan.blake"
    Write-Host "    + jordan.blake -> $helpdeskGroup" -ForegroundColor DarkGreen
}

# Delegate password reset on HR OU
$helpdeskSID = (Get-ADGroup $helpdeskGroup).SID.Value
dsacls $hrOuDN /G "${helpdeskSID}:CA;Reset Password;user" | Out-Null
dsacls $hrOuDN /G "${helpdeskSID}:WP;pwdLastSet;user"    | Out-Null
Write-Host "  DELEGATE $helpdeskGroup -> Reset Password on OU=HR" -ForegroundColor Green

# ══════════════════════════════════════════════════════════════
# BLOCK 5 — Verify everything
# ══════════════════════════════════════════════════════════════
Write-Host "`n Verifying structure:`n" -ForegroundColor Cyan

Write-Host "  OUs:" -ForegroundColor Cyan
Get-ADOrganizationalUnit -Filter * -SearchBase $DomainDN -SearchScope OneLevel |
    Select-Object Name | Format-Table -AutoSize

Write-Host "  Users by department:" -ForegroundColor Cyan
Get-ADUser -Filter * -Properties Department, Title |
    Where-Object { $_.DistinguishedName -match "OU=(IT|HR|Finance)" } |
    Select-Object Name, SamAccountName, Department, Title |
    Sort-Object Department | Format-Table -AutoSize

Write-Host "  Groups:" -ForegroundColor Cyan
Get-ADGroup -Filter * |
    Where-Object { $_.Name -like "GRP-*" } |
    Select-Object Name, GroupScope, GroupCategory |
    Format-Table -AutoSize

Write-Host " Done.`n" -ForegroundColor Cyan