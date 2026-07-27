# ============================================================
# intune-policies.ps1
# Creates Intune compliance policy and configuration profile
# Prerequisites:
#   - PowerShell 7+
#   - Microsoft.Graph module installed
#   - lab.config.ps1 filled in at repo root
#   - Device enrolled in Intune
#   - Run Connect-MgGraph before executing
# Scopes needed:
#   DeviceManagementConfiguration.ReadWrite.All
# ============================================================

. "$PSScriptRoot/../../lab.config.ps1"

Write-Host "`n Starting Intune policy creation`n" -ForegroundColor Cyan

# ══════════════════════════════════════════════════════════════
# COMPLIANCE POLICY
# Defines rules a device must meet to be marked compliant
# Non-compliant devices can be blocked via Conditional Access
# ══════════════════════════════════════════════════════════════

$compliancePolicyName = "POL-Compliance-Windows11"

# ── Idempotency check ─────────────────────────────────────────
$existingCompliance = Get-MgDeviceManagementDeviceCompliancePolicy |
    Where-Object { $_.DisplayName -eq $compliancePolicyName }

if ($existingCompliance) {
    Write-Host "  SKIP   $compliancePolicyName (already exists)" -ForegroundColor Yellow
} else {
    $compliancePolicy = @{
        "@odata.type"    = "#microsoft.graph.windows10CompliancePolicy"
        displayName      = $compliancePolicyName
        description      = "Baseline compliance policy for Windows 11 lab devices"

        # ── Device health ──────────────────────────────────────
        bitLockerEnabled            = $true     # Require BitLocker encryption
        secureBootEnabled           = $true     # Require Secure Boot
        codeIntegrityEnabled        = $true     # Require code integrity

        # ── System security ────────────────────────────────────
        firewallEnabled             = $true     # Require Windows Firewall
        antivirusRequired           = $true     # Require antivirus
        antispywareRequired         = $true     # Require antispyware
        defenderEnabled             = $true     # Require Microsoft Defender

        # ── OS version ─────────────────────────────────────────
        # 10.0.22000 = Windows 11 minimum build
        osMinimumVersion            = "10.0.22000"

        # ── Password ───────────────────────────────────────────
        passwordRequired            = $true
        passwordMinimumLength       = 8
        passwordRequiredType        = "alphanumeric"
        passwordMinutesOfInactivityBeforeLock = 5
    }

    New-MgDeviceManagementDeviceCompliancePolicy -BodyParameter $compliancePolicy | Out-Null
    Write-Host "  CREATE $compliancePolicyName" -ForegroundColor Green
}

# ── Assign compliance policy to all devices ───────────────────
$policy = Get-MgDeviceManagementDeviceCompliancePolicy |
    Where-Object { $_.DisplayName -eq $compliancePolicyName }

$existingAssignment = Get-MgDeviceManagementDeviceCompliancePolicyAssignment `
    -DeviceCompliancePolicyId $policy.Id

if ($existingAssignment) {
    Write-Host "  SKIP   Compliance policy assignment (already assigned)" -ForegroundColor Yellow
} else {
    New-MgDeviceManagementDeviceCompliancePolicyAssignment `
        -DeviceCompliancePolicyId $policy.Id `
        -BodyParameter @{
            target = @{
                "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget"
            }
        } | Out-Null
    Write-Host "  ASSIGN $compliancePolicyName → All devices" -ForegroundColor Green
}

# ══════════════════════════════════════════════════════════════
# CONFIGURATION PROFILE
# Actively pushes settings to enrolled devices
# Unlike compliance, these settings are enforced not just checked
# ══════════════════════════════════════════════════════════════

$configProfileName = "CFG-Windows11-Baseline"

# ── Idempotency check ─────────────────────────────────────────
$existingConfig = Get-MgDeviceManagementDeviceConfiguration |
    Where-Object { $_.DisplayName -eq $configProfileName }

if ($existingConfig) {
    Write-Host "  SKIP   $configProfileName (already exists)" -ForegroundColor Yellow
} else {
    $configProfile = @{
        "@odata.type"  = "#microsoft.graph.windows10GeneralConfiguration"
        displayName    = $configProfileName
        description    = "Baseline configuration profile for Windows 11 lab devices"

        # ── Lock screen ────────────────────────────────────────
        # Signs out screen after 5 minutes of inactivity
        passwordMinutesOfInactivityBeforeScreenTimeout = 5

        # ── USB storage ────────────────────────────────────────
        # Blocks writing to removable storage devices
        usbBlocked                    = $false   # Don't block USB entirely
        removableStorageBlocked       = $true    # Block removable storage write

        # ── Defender ───────────────────────────────────────────
        defenderMonitorFileActivity               = "monitorAllFiles"
        defenderScanArchiveFiles                  = $true
        defenderScanDownloads                     = $true

        # ── Windows ────────────────────────────────────────────
        windowsSpotlightBlocked                   = $false
        cortanaBlocked                            = $true
        diagnosticsDataSubmissionMode             = "basic"
    }

    New-MgDeviceManagementDeviceConfiguration -BodyParameter $configProfile | Out-Null
    Write-Host "  CREATE $configProfileName" -ForegroundColor Green
}

# ── Assign config profile to all devices ─────────────────────
$config = Get-MgDeviceManagementDeviceConfiguration |
    Where-Object { $_.DisplayName -eq $configProfileName }

$existingConfigAssignment = Get-MgDeviceManagementDeviceConfigurationAssignment `
    -DeviceConfigurationId $config.Id

if ($existingConfigAssignment) {
    Write-Host "  SKIP   Config profile assignment (already assigned)" -ForegroundColor Yellow
} else {
    New-MgDeviceManagementDeviceConfigurationAssignment `
        -DeviceConfigurationId $config.Id `
        -BodyParameter @{
            target = @{
                "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget"
            }
        } | Out-Null
    Write-Host "  ASSIGN $configProfileName → All devices" -ForegroundColor Green
}

# ── Verify ────────────────────────────────────────────────────
Write-Host "`n Verifying Intune policies:`n" -ForegroundColor Cyan

Write-Host "  Compliance policies:" -ForegroundColor Cyan
Get-MgDeviceManagementDeviceCompliancePolicy |
    Select-Object DisplayName, @{
        Name="Type"; Expression={ $_."@odata.type" -replace ".*\.",""  }
    } | Format-Table -AutoSize

Write-Host "  Configuration profiles:" -ForegroundColor Cyan
Get-MgDeviceManagementDeviceConfiguration |
    Where-Object { $_.DisplayName -like "CFG-*" } |
    Select-Object DisplayName, @{
        Name="Type"; Expression={ $_."@odata.type" -replace ".*\.",""  }
    } | Format-Table -AutoSize

Write-Host " Done.`n" -ForegroundColor Cyan