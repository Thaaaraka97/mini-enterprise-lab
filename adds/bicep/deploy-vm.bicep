// ============================================================
// deploy-vm.bicep
// Deploys a Windows Server 2022 Domain Controller VM
// Usage:
//   az deployment group create \
//     --resource-group rg-lab-adds \
//     --template-file deploy-vm.bicep \
//     --parameters adminUsername=labadmin \
//                  adminPassword=YOUR-PASSWORD \
//                  allowRdpFromIp=YOUR-PUBLIC-IP
// ============================================================

// ── Parameters ────────────────────────────────────────────────
@description('Admin username for the VM')
param adminUsername string

@description('Admin password for the VM')
@secure()
param adminPassword string

@description('Your public IP to allow RDP — find it at whatismyip.com')
param allowRdpFromIp string

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('VM size — must be available in your subscription')
param vmSize string = 'Standard_D2als_v7'

@description('Environment prefix for naming')
param prefix string = 'lab'

// ── Variables ─────────────────────────────────────────────────
var vmName         = '${prefix}-dc-01'
var vnetName       = '${prefix}-vnet-adds'
var subnetName     = 'snet-dc'
var nsgName        = '${prefix}-nsg-dc'
var pipName        = '${prefix}-pip-dc'
var nicName        = '${prefix}-nic-dc'
var osDiskName     = '${prefix}-disk-dc-os'
var vnetAddressPrefix  = '10.0.0.0/16'
var subnetPrefix       = '10.0.1.0/24'
var privateIpAddress   = '10.0.1.4'    // Static — DNS needs a fixed IP

// ── Network Security Group ────────────────────────────────────
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP-Inbound'
        properties: {
          priority:                 100
          protocol:                 'Tcp'
          access:                   'Allow'
          direction:                'Inbound'
          sourceAddressPrefix:      allowRdpFromIp    // Your IP only
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '3389'
          description:              'Allow RDP from admin IP only'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority:                 4096
          protocol:                 '*'
          access:                   'Deny'
          direction:                'Inbound'
          sourceAddressPrefix:      '*'
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '*'
          description:              'Deny all other inbound traffic'
        }
      }
    ]
  }
}

// ── Virtual Network + Subnet ──────────────────────────────────
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [ vnetAddressPrefix ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// ── Public IP ─────────────────────────────────────────────────
resource pip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: pipName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'   // Static so IP doesn't change on restart
    dnsSettings: {
      domainNameLabel: '${prefix}-dc-01'
    }
  }
}

// ── Network Interface ─────────────────────────────────────────
resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress:           privateIpAddress
          subnet: {
            id: '${vnet.id}/subnets/${subnetName}'
          }
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
  }
}

// ── Virtual Machine ───────────────────────────────────────────
resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName:         vmName
      adminUsername:        adminUsername
      adminPassword:        adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent:       true
        timeZone:               'Eastern Standard Time'
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer:     'WindowsServer'
        sku:       '2022-datacenter-azure-edition'
        version:   'latest'
      }
      osDisk: {
        name:         osDiskName
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        diskSizeGB: 128
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

// ── Auto-shutdown ─────────────────────────────────────────────
// Saves credits — shuts down at 7PM Eastern daily
resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${vmName}'
  location: location
  properties: {
    status:           'Enabled'
    taskType:         'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: '1900'             // 7PM
    }
    timeZoneId:       'Eastern Standard Time'
    targetResourceId: vm.id
    notificationSettings: {
      status: 'Disabled'
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────
output vmName          string = vm.name
output publicIpAddress string = pip.properties.ipAddress
output privateIpAddress string = privateIpAddress
output rdpCommand      string = 'remmina rdp://${adminUsername}@${pip.properties.ipAddress}'
output fqdn            string = pip.properties.dnsSettings.fqdn
