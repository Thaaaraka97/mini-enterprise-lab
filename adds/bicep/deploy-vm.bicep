// ============================================================
// deploy-vm.bicep
// Generic reusable VM template
// All values driven by parameters — no hardcoded specifics
// Usage: called by deploy.sh with different parameter sets
// ============================================================

// ── Parameters ────────────────────────────────────────────────
@description('VM name')
param vmName string

@description('Admin username')
param adminUsername string

@description('Admin password')
@secure()
param adminPassword string

@description('Your public IP to allow RDP')
param allowRdpFromIp string

@description('Azure region')
param location string = resourceGroup().location

@description('VM size')
param vmSize string = 'Standard_D2als_v7'

@description('OS image publisher')
param imagePublisher string = 'MicrosoftWindowsServer'

@description('OS image offer')
param imageOffer string = 'WindowsServer'

@description('OS image SKU')
param imageSku string = '2022-datacenter-azure-edition'

@description('Static private IP address')
param privateIpAddress string

@description('Auto-shutdown time in HHMM format')
param autoShutdownTime string = '1900'

@description('Timezone for auto-shutdown')
param timeZoneId string = 'Eastern Standard Time'

@description('OS disk size in GB')
param osDiskSizeGB int = 128

// ── Variables ─────────────────────────────────────────────────
var vnetName       = 'lab-vnet-adds'
var subnetName     = 'snet-dc'
var nsgName        = '${vmName}-nsg'
var pipName        = '${vmName}-pip'
var nicName        = '${vmName}-nic'
var osDiskName     = '${vmName}-disk-os'

// ── NSG ───────────────────────────────────────────────────────
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
          sourceAddressPrefix:      allowRdpFromIp
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '3389'
          description:              'Allow RDP from admin IP only'
        }
      }
      {
        name: 'Allow-Internal-Inbound'
        properties: {
          priority:                 200
          protocol:                 '*'
          access:                   'Allow'
          direction:                'Inbound'
          sourceAddressPrefix:      '10.0.1.0/24'
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '*'
          description:              'Allow all internal subnet traffic'
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
          description:              'Deny all other inbound'
        }
      }
    ]
  }
}

// ── VNet — only deploy if it doesn't exist ────────────────────
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [ '10.0.0.0/16' ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
    ]
  }
}

// ── Public IP ─────────────────────────────────────────────────
resource pip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: pipName
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: vmName
    }
  }
}

// ── NIC ───────────────────────────────────────────────────────
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
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

// ── VM ────────────────────────────────────────────────────────
resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName:  vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent:       true
        timeZone:               timeZoneId
      }
    }
    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer:     imageOffer
        sku:       imageSku
        version:   'latest'
      }
      osDisk: {
        name:         osDiskName
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        diskSizeGB: osDiskSizeGB
      }
    }
    networkProfile: {
      networkInterfaces: [
        { id: nic.id }
      ]
    }
  }
}

// ── Auto-shutdown ─────────────────────────────────────────────
resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${vmName}'
  location: location
  properties: {
    status:    'Enabled'
    taskType:  'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTime
    }
    timeZoneId:       timeZoneId
    targetResourceId: vm.id
    notificationSettings: {
      status: 'Disabled'
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────
output vmName           string = vm.name
output publicIpAddress  string = pip.properties.ipAddress
output privateIpAddress string = privateIpAddress
output fqdn             string = pip.properties.dnsSettings.fqdn
output rdpCommand       string = 'remmina rdp://${adminUsername}@${pip.properties.ipAddress}'
