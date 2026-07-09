// =============================================================================
// SQL Server + AI DBA Copilot Demo - Azure infrastructure (Bicep)
// -----------------------------------------------------------------------------
// Deploys a minimal, demo-friendly estate that mimics an on-prem SQL Server
// footprint:
//   - 1 virtual network with 2 subnets (jumpbox + SQL)
//   - 1 Windows Server 2022 jumpbox VM (public IP, RDP locked to your IP)
//   - 1 SQL Server 2022 (Standard) on Windows Server 2022 VM (PRIVATE only)
//   - NSGs so SQL (TCP 1433) is reachable ONLY from the jumpbox subnet
//
// This is NOT a production reference. It favors simplicity and reproducibility.
// See README.md "On-prem parallels" and "Security and guardrails".
//
// Scope: resource group. Deploy with infra/deploy.ps1.
// =============================================================================

targetScope = 'resourceGroup'

// ----------------------------- Parameters ------------------------------------

@description('Azure region for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Short prefix (3-10 lowercase chars) used to name resources, e.g. "wwidemo".')
@minLength(3)
@maxLength(10)
param namePrefix string = 'wwidemo'

@description('Local administrator username for BOTH VMs.')
@minLength(4)
@maxLength(20)
param adminUsername string

@description('Local administrator password for BOTH VMs. Supply at deploy time; never commit it.')
@secure()
@minLength(12)
param adminPassword string

@description('Public IP address or CIDR allowed to RDP the jumpbox, e.g. "203.0.113.10/32". Find yours at https://ifconfig.me. Use a /32 for a single IP.')
param allowedRdpSourceIp string

@description('VM size for the jumpbox (DBA workstation).')
param jumpboxVmSize string = 'Standard_D2as_v6'

@description('VM size for the SQL Server VM. E-series gives more memory for SQL.')
param sqlVmSize string = 'Standard_E4as_v6'

@description('SQL Server 2022 image SKU. "standard-gen2" = Standard edition (license billed via PAYG).')
@allowed([
  'standard-gen2'
  'enterprise-gen2'
  'sqldev-gen2'
])
param sqlImageSku string = 'standard-gen2'

@description('SQL Server license model. PAYG bills the SQL license hourly. Use AHUB only if you bring your own license.')
@allowed([
  'PAYG'
  'AHUB'
])
param sqlServerLicenseType string = 'PAYG'

@description('SQL Server authentication login created on the SQL VM (mixed mode). Used by SSMS from the jumpbox.')
@minLength(4)
@maxLength(30)
param sqlAuthLogin string = 'demodba'

@description('Password for the SQL authentication login. Supply at deploy time; never commit it.')
@secure()
@minLength(12)
param sqlAuthPassword string

@description('Address space for the virtual network.')
param vnetAddressPrefix string = '10.20.0.0/16'

@description('Address prefix for the jumpbox subnet.')
param jumpboxSubnetPrefix string = '10.20.1.0/24'

@description('Address prefix for the SQL subnet.')
param sqlSubnetPrefix string = '10.20.2.0/24'

// ----------------------------- Variables -------------------------------------

var suffix = uniqueString(resourceGroup().id)
var vnetName = '${namePrefix}-vnet'
var jumpboxSubnetName = 'snet-jumpbox'
var sqlSubnetName = 'snet-sql'
var jumpboxNsgName = '${namePrefix}-nsg-jumpbox'
var sqlNsgName = '${namePrefix}-nsg-sql'
var jumpboxPipName = '${namePrefix}-jumpbox-pip'
var jumpboxNicName = '${namePrefix}-jumpbox-nic'
var sqlNicName = '${namePrefix}-sql-nic'
var jumpboxVmName = '${namePrefix}-jump'
var sqlVmName = '${namePrefix}-sql'
var jumpboxDnsLabel = toLower('${namePrefix}-jump-${suffix}')

// --------------------------- Network security --------------------------------

resource jumpboxNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: jumpboxNsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP-From-AllowedIp'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: allowedRdpSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
          description: 'RDP to the jumpbox is restricted to the provided source IP/CIDR only.'
        }
      }
    ]
  }
}

resource sqlNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: sqlNsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SQL-From-JumpboxSubnet'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: jumpboxSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '1433'
          description: 'SQL Server (TCP 1433) is reachable ONLY from the jumpbox subnet.'
        }
      }
      {
        name: 'Allow-RDP-From-JumpboxSubnet'
        properties: {
          priority: 1010
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: jumpboxSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
          description: 'Optional: RDP the SQL VM from the jumpbox only (no public exposure).'
        }
      }
      {
        name: 'Allow-WinRM-From-JumpboxSubnet'
        properties: {
          priority: 1020
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: jumpboxSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5985'
          description: 'WinRM/PS-Remoting (TCP 5985) from the jumpbox subnet only - used by 02-copy-backup-to-sqlvm.ps1.'
        }
      }
      {
        name: 'Deny-All-Inbound-From-Internet'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Explicit belt-and-suspenders deny of any inbound traffic from the internet.'
        }
      }
    ]
  }
}

// ------------------------------- Network -------------------------------------

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: jumpboxSubnetName
        properties: {
          addressPrefix: jumpboxSubnetPrefix
          networkSecurityGroup: {
            id: jumpboxNsg.id
          }
        }
      }
      {
        name: sqlSubnetName
        properties: {
          addressPrefix: sqlSubnetPrefix
          networkSecurityGroup: {
            id: sqlNsg.id
          }
        }
      }
    ]
  }
}

resource jumpboxPip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: jumpboxPipName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: jumpboxDnsLabel
    }
  }
}

resource jumpboxNic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: jumpboxNicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${vnet.id}/subnets/${jumpboxSubnetName}'
          }
          publicIPAddress: {
            id: jumpboxPip.id
          }
        }
      }
    ]
  }
}

resource sqlNic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: sqlNicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          // Static private IP keeps the SSMS connection target stable across reboots.
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.20.2.10'
          subnet: {
            id: '${vnet.id}/subnets/${sqlSubnetName}'
          }
          // No publicIPAddress: the SQL VM is never exposed to the internet.
        }
      }
    ]
  }
}

// -------------------------------- Jumpbox VM ---------------------------------

resource jumpboxVm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: jumpboxVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: jumpboxVmSize
    }
    osProfile: {
      computerName: jumpboxVmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: jumpboxNic.id
        }
      ]
    }
  }
}

// -------------------------------- SQL Server VM ------------------------------

resource sqlVm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: sqlVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: sqlVmSize
    }
    osProfile: {
      computerName: sqlVmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftSQLServer'
        offer: 'sql2022-ws2022'
        sku: sqlImageSku
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: sqlNic.id
        }
      ]
    }
  }
}

// SQL IaaS Agent extension configuration: enables mixed-mode (SQL) authentication,
// creates the SQL login, and binds SQL Server to private connectivity on TCP 1433.
resource sqlVirtualMachine 'Microsoft.SqlVirtualMachine/sqlVirtualMachines@2023-10-01' = {
  name: sqlVmName
  location: location
  properties: {
    virtualMachineResourceId: sqlVm.id
    sqlServerLicenseType: sqlServerLicenseType
    sqlManagement: 'Full'
    serverConfigurationsManagementSettings: {
      sqlConnectivityUpdateSettings: {
        connectivityType: 'PRIVATE'
        port: 1433
        sqlAuthUpdateUserName: sqlAuthLogin
        sqlAuthUpdatePassword: sqlAuthPassword
      }
    }
  }
}

// -------------------------------- Outputs ------------------------------------

@description('Public DNS name of the jumpbox - RDP target.')
output jumpboxFqdn string = jumpboxPip.properties.dnsSettings.fqdn

@description('Public IP of the jumpbox - RDP target.')
output jumpboxPublicIp string = jumpboxPip.properties.ipAddress

@description('Private IP of the SQL Server VM - SSMS connection target from the jumpbox.')
output sqlServerPrivateIp string = sqlNic.properties.ipConfigurations[0].properties.privateIPAddress

@description('SQL VM computer name (also usable as the server name from the jumpbox over private DNS).')
output sqlServerComputerName string = sqlVmName

@description('SQL authentication login created on the SQL VM.')
output sqlAuthLoginName string = sqlAuthLogin
