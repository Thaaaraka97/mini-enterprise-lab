# ============================================================
# install-ad.ps1
# Installs AD DS role and promotes server to Domain Controller
# Run as Administrator inside the Windows Server VM
# Server will reboot automatically after promotion
# ============================================================

# ── Configuration ─────────────────────────────────────────────
$DomainName     = "corp.local"
$NetbiosName    = "CORP"

# ── Step 1 — Install AD DS role ───────────────────────────────
Write-Host "`n Installing AD DS role..." -ForegroundColor Cyan

Install-WindowsFeature `
    -Name AD-Domain-Services `
    -IncludeManagementTools `
    -IncludeAllSubFeature

Write-Host "  AD DS role installed" -ForegroundColor Green

# ── Step 2 — Install DNS role ─────────────────────────────────
# DNS is critical — AD DS won't work without it
Write-Host "`n Installing DNS role..." -ForegroundColor Cyan

Install-WindowsFeature `
    -Name DNS `
    -IncludeManagementTools

Write-Host "  DNS role installed" -ForegroundColor Green

# ── Step 3 — Import AD DS module ─────────────────────────────
Import-Module ADDSDeployment

# ── Step 4 — Promote to Domain Controller ────────────────────
# This creates a new forest — use only on a fresh server
# Server reboots automatically when complete
Write-Host "`n Promoting server to Domain Controller..." -ForegroundColor Cyan
Write-Host "  Domain: $DomainName" -ForegroundColor Cyan
Write-Host "  NetBIOS: $NetbiosName" -ForegroundColor Cyan
Write-Host "  Server will reboot automatically`n" -ForegroundColor Yellow

# Prompt securely — never hardcode DSRM password
# Used to log in if AD breaks — save this somewhere safe
$SafeModePassword = Read-Host -Prompt "Enter Safe Mode (DSRM) password" -AsSecureString

Install-ADDSForest `
    -DomainName        $DomainName `
    -DomainNetbiosName $NetbiosName `
    -ForestMode        "WinThreshold" `
    -DomainMode        "WinThreshold" `
    -InstallDns `
    -SafeModeAdministratorPassword $SafeModePassword `
    -Force
# NoRebootOnCompletion = false means it reboots automatically
# Don't set it to true — AD won't function properly until rebooted