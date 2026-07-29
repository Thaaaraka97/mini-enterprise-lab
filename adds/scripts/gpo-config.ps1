# ============================================================
# gpo-config.ps1
# Creates and links Group Policy Objects
# Run as Administrator on the Domain Controller
# Prerequisites: AD DS installed, OUs created
# ============================================================

$DomainDN   = "DC=corp,DC=local"
$DomainName = "corp.local"

# ══════════════════════════════════════════════════════════════
# BLOCK 1 — Password Policy (domain level)
# Must be linked at domain level to affect domain accounts
# ══════════════════════════════════════════════════════════════
Write-Host "`n Setting domain password policy..." -ForegroundColor Cyan

# Set password policy via Fine-Grained or Default Domain Policy
# The most reliable way for domain-wide password policy
Set-ADDefaultDomainPasswordPolicy `
    -Identity              $DomainName `
    -MinPasswordLength     12 `
    -PasswordHistoryCount  10 `
    -MaxPasswordAge        (New-TimeSpan -Days 90) `
    -MinPasswordAge        (New-TimeSpan -Days 1) `
    -ComplexityEnabled     $true `
    -LockoutThreshold      5 `
    -LockoutDuration       (New-TimeSpan -Minutes 15) `
    -LockoutObservationWindow (New-TimeSpan -Minutes 15)

Write-Host "  SET    Domain password policy" -ForegroundColor Green

# ══════════════════════════════════════════════════════════════
# BLOCK 2 — Login Banner (domain level)
# Legal warning displayed before every login
# ══════════════════════════════════════════════════════════════
Write-Host "`n Creating Login Banner GPO..." -ForegroundColor Cyan

$gpoName = "GPO-Login-Banner"
$existing = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
if (-not $existing) {
    New-GPO -Name $gpoName -Comment "Legal login banner" | Out-Null

    # Banner title
    Set-GPRegistryValue -Name $gpoName `
        -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -ValueName "legalnoticecaption" `
        -Type String `
        -Value "Authorized Access Only"

    # Banner text
    Set-GPRegistryValue -Name $gpoName `
        -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -ValueName "legalnoticetext" `
        -Type String `
        -Value "This system is for authorized users only. All activity is monitored and logged. Unauthorized access is prohibited and subject to prosecution."

    New-GPLink -Name $gpoName -Target $DomainDN -LinkEnabled Yes | Out-Null
    Write-Host "  CREATE + LINK $gpoName -> $DomainName" -ForegroundColor Green
} else {
    Write-Host "  SKIP   $gpoName (already exists)" -ForegroundColor Yellow
}

# ══════════════════════════════════════════════════════════════
# BLOCK 3 — Lock Screen timeout (all OUs)
# Signs out screen after 5 minutes of inactivity
# ══════════════════════════════════════════════════════════════
Write-Host "`n Creating Lock Screen GPO..." -ForegroundColor Cyan

$gpoName = "GPO-Lock-Screen"
$existing = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
if (-not $existing) {
    New-GPO -Name $gpoName -Comment "5 minute screen lock timeout" | Out-Null

    Set-GPRegistryValue -Name $gpoName `
        -Key "HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop" `
        -ValueName "ScreenSaveTimeOut" `
        -Type String `
        -Value "300"

    Set-GPRegistryValue -Name $gpoName `
        -Key "HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop" `
        -ValueName "ScreenSaveActive" `
        -Type String `
        -Value "1"

    Set-GPRegistryValue -Name $gpoName `
        -Key "HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop" `
        -ValueName "ScreenSaverIsSecure" `
        -Type String `
        -Value "1"

    # Link to all three OUs
    foreach ($ou in @("IT","HR","Finance")) {
        New-GPLink `
            -Name        $gpoName `
            -Target      "OU=$ou,$DomainDN" `
            -LinkEnabled Yes | Out-Null
        Write-Host "  LINK   $gpoName -> OU=$ou" -ForegroundColor Green
    }
    Write-Host "  CREATE $gpoName" -ForegroundColor Green
} else {
    Write-Host "  SKIP   $gpoName (already exists)" -ForegroundColor Yellow
}

# ══════════════════════════════════════════════════════════════
# BLOCK 4 — USB Storage Restriction (Finance OU only)
# Blocks write access to removable storage for Finance users
# ══════════════════════════════════════════════════════════════
Write-Host "`n Creating USB Restriction GPO..." -ForegroundColor Cyan

$gpoName = "GPO-USB-Restriction"
$existing = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
if (-not $existing) {
    New-GPO -Name $gpoName -Comment "Block removable storage writes - Finance only" | Out-Null

    # Deny write access to removable disks
    Set-GPRegistryValue -Name $gpoName `
        -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}" `
        -ValueName "Deny_Write" `
        -Type DWord `
        -Value 1

    # Deny write access to removable disk devices
    Set-GPRegistryValue -Name $gpoName `
        -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{53f56311-b6bf-11d0-94f2-00a0c91efb8b}" `
        -ValueName "Deny_Write" `
        -Type DWord `
        -Value 1

    New-GPLink `
        -Name        $gpoName `
        -Target      "OU=Finance,$DomainDN" `
        -LinkEnabled Yes | Out-Null

    Write-Host "  CREATE + LINK $gpoName -> OU=Finance" -ForegroundColor Green
} else {
    Write-Host "  SKIP   $gpoName (already exists)" -ForegroundColor Yellow
}

# ══════════════════════════════════════════════════════════════
# BLOCK 5 — Verify
# ══════════════════════════════════════════════════════════════
Write-Host "`n Verifying GPOs:`n" -ForegroundColor Cyan

Get-GPO -All |
    Where-Object { $_.DisplayName -like "GPO-*" } |
    Select-Object DisplayName, GpoStatus |
    Format-Table -AutoSize

Write-Host "`n GPO links per OU:`n" -ForegroundColor Cyan
foreach ($ou in @("IT","HR","Finance")) {
    Write-Host "  OU=$ou" -ForegroundColor Cyan
    $links = (Get-ADOrganizationalUnit `
        -Filter "Name -eq '$ou'" `
        -Properties LinkedGroupPolicyObjects).LinkedGroupPolicyObjects
    foreach ($link in $links) {
        $guid = $link -replace ".*\{(.*)\}.*",'$1'
        $gpo  = Get-GPO -Guid $guid -ErrorAction SilentlyContinue
        if ($gpo) {
            Write-Host "    -> $($gpo.DisplayName)" -ForegroundColor DarkGreen
        }
    }
}

Write-Host "`n Password policy:`n" -ForegroundColor Cyan
Get-ADDefaultDomainPasswordPolicy -Identity $DomainName |
    Select-Object MinPasswordLength, PasswordHistoryCount,
                  MaxPasswordAge, ComplexityEnabled,
                  LockoutThreshold, LockoutDuration |
    Format-List

Write-Host " Done.`n" -ForegroundColor Cyan