// ============================================================
// deploy-vm.bicep
// Generic reusable Windows VM template
// ============================================================

// ── Parameters ────────────────────────────────────────────────

@description('VM name')
param vmName string

@description('Admin username')
param adminUsername string

@description('Admin password')
@secure()
param adminPassword string

@description('Your public IP to allow RDP, e.g. 1.2.3.4/32')
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

var vnetName   = 'lab-vnet-adds'
var subnetName = 'snet-dc'

var vnetAddressSpace = '10.0.0.0/16'
var dcSubnet         = '10.0.1.0/24'

var nsgName    = '${vmName}-nsg'
var pipName    = '${vmName}-pip'
var nicName    = '${vmName}-nic'
var osDiskName = '${vmName}-disk-os'

// ── Network Security Group ────────────────────────────────────

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location

  properties: {
    securityRules: [

      // --------------------------------------------------------
      // RDP from administrator public IP
      // --------------------------------------------------------
      {
        name: 'Allow-RDP-Admin'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'

          sourceAddressPrefix: allowRdpFromIp
          sourcePortRange: '*'

          destinationAddressPrefix: '*'
          destinationPortRange: '3389'

          description: 'Allow RDP from administrator public IP only'
        }
      }

      // --------------------------------------------------------
      // DNS - TCP
      // --------------------------------------------------------
      {
        name: 'Allow-AD-DNS-TCP'
        properties: {
          priority: 200
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'

          sourceAddressPrefix: vnetAddressSpace
          sourcePortRange: '*'

          destinationAddressPrefix: '*'
          destinationPortRange: '53'

          description: 'Allow Active Directory DNS TCP from VNet'
        }
      }

      // --------------------------------------------------------
      // DNS - UDP
      // --------------------------------------------------------
      {
        name: 'Allow-AD-DNS-UDP'
        properties: {
          priority: 210
          protocol: 'Udp'
          access: 'Allow'
          direction: 'Inbound'

          sourceAddressPrefix: vnetAddressSpace
          sourcePortRange: '*'

          destinationAddressPrefix: '*'
          destinationPortRange: '53'

          description: 'Allow Active Directory DNS UDP from VNet'
        }
      }

      // --------------------------------------------------------
      // Kerberos - TCP
      // --------------------------------------------------------
      {
        name: 'Allow-AD-Kerberos-TCP'
        properties: {
          priority: 220
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'

          sourceAddressPrefix: vnetAddressSpace
          sourcePortRange: '*'

          destinationAddressPrefix: '*'
          destinationPortRange: '88'

          description: 'Allow Kerberos authentication TCP from VNet'
        }
      }

      // --------------------------------------------------------
      // Kerberos - UDP
      // --------------------------------------------------------
      {
        name: 'Allow-AD-Kerberos-UDP'
        properties: {
          priority: 230
          protocol: 'Udp'
          access: 'Allow'
          direction: 'Inbound'

          sourceAddressPrefix: vnetAddressSpace
          sourcePortRange: '*'

          destinationAddressPrefix: '*'
          destinationPortRange: '88'

          description: 'Allow Kerberos authentication UDP from VNet'
        }
      }

      // --------------------------------------------------------
      // NTP / Windows Time
      // --------------------------------------------------------
      {
        name: 'Allow-AD-NTP'
        properties: {
          priority: 240
          protocol: 'Udp'
          access: 'Allow'
          direction: 'Inbound'

          sourceAddressPrefix: vnetAddressSpace
          sourcePortRange: '*'

          destinationAddressPrefix: '*'
          destinationPortRange: '123'

          description: 'Allow Windows Time from VNet'
        }
      }

      // --------------------------------------------------------
      // RPC Endpoint Mapper
      // --------------------------------------------------------
      {
        name: 'Allow-AD-RPC-Endpoint'
        properties: {
          priority: 250
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'

          sourceAddressPrefix: vnetAddressSpace
          sourcePortRange: '*'

          destinationAddressPrefix: '*'
          destinationPortRange: '135'

          description: 'Allow RPC Endpoint Mapper from VNet'
        }
      }

      // --------------------------------------------------------
      // LDAP - TCP
      // --------------------------------------------------------
      {
        name: 'Allow-AD-LDAP-TCP'
        properties: {
          priority: 260
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'

          sourceAddressPrefix: vnetAddressSpace
          sourcePortRange: '*'

          destinationAddressPrefix: '*'
          destinationPortRange: '389'

          description: 'Allow LDAP TCP from VNet'
        }
      }

      // --------------------------------------------------------
      // LDAP - UDP
      // Required for DC Locator LDAP ping
      // --------------------------------------------------------
      {
        name: 'Allow-AD-LDAP-UDP'
        properties: {
          priority: 270
          protocol: 'Udp'
          access: 'Allow'
          direction: 'Inbound'

          sourceAddressPrefix: vnetAddressSpace
          sourcePortRange: '*'

          destinationAddressPrefix: '*'
          destinationPortRange: '389'

          description: 'Allow LDAP UDP for domain controller discovery'
        }
      }

      // --------------------------------------------------------
      // SMB
      // --------------------------------------------------------
      {
        name: 'Allow-AD-SMB'
        properties: {
          priority: 280
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'

          sourceAddressPrefix: vnetAddressSpace
          sourcePortRange: '*'

          destinationAddressPrefix: '*'
          destinationPortRange: '445'

          description: 'Allow SMB for SYSVOL, NETLOGON and Group Policy'
        }
      }

      // --------------------------------------------------------
      // Kerberos Password Change - TCP
      // --------------------------------------------------------
      {
        name: 'Allow-AD-Kpasswd-TCP'
        properties: {
          priority: 290
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'

          sourceAddressPrefix: vnetAddressSpace
          sourcePortRange: '*'

          destinationAddressPrefix: '*'
          destinationPortRange: '464'

          description: 'Allow Kerberos password changes TCP'
        }
      }

      // --------------------------------------------------------
      // Kerberos Password Change - UDP
      // --------------------------------------------------------
      {
        name: 'Allow-AD-Kpasswd-UDP'
        properties: {
          priority: 300
          protocol: 'Udp'
          access: 'Allow'
          direction: 'Inbound'

          sourceAddressPrefix: vnetAddressSpace
          sourcePortRange: '*'

          destinationAddressPrefix: '*'
          destinationPortRange: '464'

          description: 'Allow Kerberos password changes UDP'
        }
      }

      // --------------------------------------------------------
      // Global Catalog
      // --------------------------------------------------------
      {
        name: 'Allow-AD-GlobalCatalog'
        properties: {
          priority: 310
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'

          sourceAddressPrefix: vnetAddressSpace
          sourcePortRange: '*'

          destinationAddressPrefix: '*'
          destinationPortRange: '3268'

          description: 'Allow Active Directory Global Catalog'
        }
      }

      // --------------------------------------------------------
      // RPC Dynamic Ports
      // --------------------------------------------------------
      {
        name: 'Allow-AD-RPC-Dynamic'
        properties: {
          priority: 320
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'

          sourceAddressPrefix: vnetAddressSpace
          sourcePortRange: '*'

          destinationAddressPrefix: '*'
          destinationPortRange: '49152-65535'

          description: 'Allow Active Directory dynamic RPC ports'
        }
      }

      // --------------------------------------------------------
      // Explicit final deny
      // --------------------------------------------------------
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'

          sourceAddressPrefix: '*'
          sourcePortRange: '*'

          destinationAddressPrefix: '*'
          destinationPortRange: '*'

          description: 'Deny all other inbound traffic'
        }
      }
    ]
  }
}

// ── Virtual Network ───────────────────────────────────────────

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location

  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }

    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: dcSubnet
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
    publicIPAllocationMethod: 'Static'

    dnsSettings: {
      domainNameLabel: vmName
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
          privateIPAddress: privateIpAddress

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

// ── Virtual Machine ───────────────────────────────────────────

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location

  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }

    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword

      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
        timeZone: timeZoneId
      }
    }

    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer: imageOffer
        sku: imageSku
        version: 'latest'
      }

      osDisk: {
        name: osDiskName
        createOption: 'FromImage'
        diskSizeGB: osDiskSizeGB

        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
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

resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${vmName}'
  location: location

  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'

    dailyRecurrence: {
      time: autoShutdownTime
    }

    timeZoneId: timeZoneId
    targetResourceId: vm.id

    notificationSettings: {
      status: 'Disabled'
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────

output vmName string = vm.name
output publicIpAddress string = pip.properties.ipAddress
output privateIpAddress string = privateIpAddress
output fqdn string = pip.properties.dnsSettings.fqdn
output rdpCommand string = 'remmina rdp://${adminUsername}@${pip.properties.ipAddress}'
