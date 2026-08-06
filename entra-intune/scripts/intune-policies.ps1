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
# CLEANUP — remove any previously failed policies
# ══════════════════════════════════════════════════════════════
$failedCompliance = Get-MgDeviceManagementDeviceCompliancePolicy |
    Where-Object { $_.DisplayName -eq "POL-Compliance-Windows11" }
if ($failedCompliance) {
    Remove-MgDeviceManagementDeviceCompliancePolicy `
        -DeviceCompliancePolicyId $failedCompliance.Id
    Write-Host "  CLEAN  Removed failed compliance policy" -ForegroundColor Yellow
}

$failedConfig = Get-MgDeviceManagementDeviceConfiguration |
    Where-Object { $_.DisplayName -eq "CFG-Windows11-Baseline" }
if ($failedConfig) {
    Remove-MgDeviceManagementDeviceConfiguration `
        -DeviceConfigurationId $failedConfig.Id
    Write-Host "  CLEAN  Removed failed config profile" -ForegroundColor Yellow
}

# ══════════════════════════════════════════════════════════════
# COMPLIANCE POLICY
# ══════════════════════════════════════════════════════════════
$compliancePolicyName = "POL-Compliance-Windows11"

Write-Host "  Creating compliance policy..." -ForegroundColor Cyan

$compliancePolicy = @{
    "@odata.type" = "#microsoft.graph.windows10CompliancePolicy"
    displayName   = $compliancePolicyName
    description   = "Baseline compliance policy for Windows 11 lab devices"

    # ── Device health ──────────────────────────────────────
    bitLockerEnabled     = $true
    secureBootEnabled    = $true
    codeIntegrityEnabled = $true

    # ── System security ────────────────────────────────────
    firewallEnabled     = $true
    antivirusRequired   = $true
    antispywareRequired = $true
    defenderEnabled     = $true

    # ── OS version ─────────────────────────────────────────
    osMinimumVersion = "10.0.22000"

    # ── Password ───────────────────────────────────────────
    passwordRequired                      = $true
    passwordMinimumLength                 = 8
    passwordRequiredType                  = "alphanumeric"
    passwordMinutesOfInactivityBeforeLock = 5

    # ── Required scheduled action ──────────────────────────
    # Intune API requires exactly one scheduled action
    # block with gracePeriodHours 0 = non-compliant immediately
    scheduledActionsForRule = @(
        @{
            ruleName = "PasswordRequired"
            scheduledActionConfigurations = @(
                @{
                    actionType                = "block"
                    gracePeriodHours          = 0
                    notificationTemplateId    = ""
                    notificationMessageCCList = @()
                }
            )
        }
    )
}

$newPolicy = New-MgDeviceManagementDeviceCompliancePolicy `
    -BodyParameter $compliancePolicy
Write-Host "  CREATE $compliancePolicyName" -ForegroundColor Green

# ── Assign compliance policy to all devices ───────────────
# Uses Invoke-MgGraphRequest with /assign action endpoint
# New-MgDeviceManagementDeviceCompliancePolicyAssignment is
# not supported on this API version
Invoke-MgGraphRequest `
    -Method POST `
    -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies/$($newPolicy.Id)/assign" `
    -Body (@{
        assignments = @(
            @{
                target = @{
                    "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget"
                }
            }
        )
    } | ConvertTo-Json -Depth 10) `
    -ContentType "application/json" | Out-Null

Write-Host "  ASSIGN $compliancePolicyName -> All devices" -ForegroundColor Green

# ══════════════════════════════════════════════════════════════
# CONFIGURATION PROFILE
# Actively pushes settings to enrolled devices
# Unlike compliance, these settings are enforced not just checked
# ══════════════════════════════════════════════════════════════
$configProfileName = "CFG-Windows11-Baseline"

Write-Host "`n  Creating configuration profile..." -ForegroundColor Cyan

$configProfile = @{
    "@odata.type" = "#microsoft.graph.windows10GeneralConfiguration"
    displayName   = $configProfileName
    description   = "Baseline configuration profile for Windows 11 lab devices"

    # ── Lock screen ────────────────────────────────────────
    passwordMinutesOfInactivityBeforeScreenTimeout = 5

    # ── USB / removable storage ────────────────────────────
    usbBlocked              = $false
    removableStorageBlocked = $true

    # ── Defender ───────────────────────────────────────────
    defenderMonitorFileActivity  = "monitorAllFiles"
    defenderScanArchiveFiles     = $true
    defenderScanDownloads        = $true

    # ── Windows settings ───────────────────────────────────
    cortanaBlocked                = $true
    diagnosticsDataSubmissionMode = "basic"
}

$newConfig = New-MgDeviceManagementDeviceConfiguration `
    -BodyParameter $configProfile
Write-Host "  CREATE $configProfileName" -ForegroundColor Green

# ── Assign config profile to all devices ─────────────────
Invoke-MgGraphRequest `
    -Method POST `
    -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations/$($newConfig.Id)/assign" `
    -Body (@{
        assignments = @(
            @{
                target = @{
                    "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget"
                }
            }
        )
    } | ConvertTo-Json -Depth 10) `
    -ContentType "application/json" | Out-Null

Write-Host "  ASSIGN $configProfileName -> All devices" -ForegroundColor Green

# ══════════════════════════════════════════════════════════════
# VERIFY
# ══════════════════════════════════════════════════════════════
Write-Host "`n Verifying Intune policies:`n" -ForegroundColor Cyan

Write-Host "  Compliance policies:" -ForegroundColor Cyan
Get-MgDeviceManagementDeviceCompliancePolicy |
    Select-Object DisplayName, @{
        Name="Type"
        Expression={ $_."@odata.type" -replace ".*\.",""  }
    } | Format-Table -AutoSize

Write-Host "  Configuration profiles:" -ForegroundColor Cyan
Get-MgDeviceManagementDeviceConfiguration |
    Where-Object { $_.DisplayName -like "CFG-*" } |
    Select-Object DisplayName, @{
        Name="Type"
        Expression={ $_."@odata.type" -replace ".*\.",""  }
    } | Format-Table -AutoSize

Write-Host " Done.`n" -ForegroundColor Cyan