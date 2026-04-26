// =============================================================================
// Consumer module — connects to the provider's service via a Private Endpoint
// =============================================================================
// Resources:
//   - Consumer VNet (10.20.0.0/16)
//       * snet-jumpbox (10.20.1.0/24)  -> jumpbox VM with public IP for SSH
//       * snet-pe      (10.20.2.0/24)  -> Private Endpoint NICs
//   - Public IP + jumpbox Linux VM (test client)
//   - Private Endpoint targeting the provider's Private Link Service
//
// NOTE: There is NO VNet peering between provider and consumer VNets.
// All traffic flows over the Microsoft backbone via Private Link.
// =============================================================================

@description('Azure region.')
param location string

@description('Resource name prefix.')
param namePrefix string

@description('Admin username for the jumpbox VM.')
param adminUsername string

@description('SSH public key.')
@secure()
param sshPublicKey string

@description('VM size for the jumpbox.')
param vmSize string

@description('Resource ID of the Private Link Service to connect to.')
param privateLinkServiceId string

var consumerVnetName = '${namePrefix}-consumer-vnet'
var jumpboxSubnetName = 'snet-jumpbox'
var peSubnetName = 'snet-pe'
var jumpboxNsgName = '${namePrefix}-jumpbox-nsg'
var peName = '${namePrefix}-pe-to-provider'

// Custom Private DNS zone for the provider service (option 2 in the README).
// We create the zone + VNet link in Bicep; the A record is added post-deploy
// from deploy.sh once Azure has assigned the PE NIC its private IP.
var providerDnsZoneName = 'provider.internal'
var providerHostname = 'app'

// ---------------------------------------------------------------------------
// NSG for jumpbox subnet — SSH only.
// (Tighten sourceAddressPrefix to your IP for real use.)
// ---------------------------------------------------------------------------
resource jumpboxNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: jumpboxNsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-Inbound'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Consumer VNet with two subnets.
// The PE subnet does NOT need to disable privateLinkServiceNetworkPolicies,
// but privateEndpointNetworkPolicies controls NSG/route propagation on the PE.
// ---------------------------------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: consumerVnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [ '10.20.0.0/16' ]
    }
    subnets: [
      {
        name: jumpboxSubnetName
        properties: {
          addressPrefix: '10.20.1.0/24'
          networkSecurityGroup: { id: jumpboxNsg.id }
        }
      }
      {
        name: peSubnetName
        properties: {
          addressPrefix: '10.20.2.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource jumpboxSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  parent: vnet
  name: jumpboxSubnetName
}

resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  parent: vnet
  name: peSubnetName
}

// ---------------------------------------------------------------------------
// Jumpbox: Public IP + NIC + Linux VM.
// ---------------------------------------------------------------------------
resource jumpboxPip 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: '${namePrefix}-jumpbox-pip'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource jumpboxNic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: '${namePrefix}-jumpbox-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipcfg'
        properties: {
          subnet: { id: jumpboxSubnet.id }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: { id: jumpboxPip.id }
        }
      }
    ]
  }
}

var jumpboxCloudInit = '''
#cloud-config
package_update: true
packages:
  - curl
  - dnsutils
  - net-tools
'''

resource jumpbox 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: '${namePrefix}-jumpbox'
  location: location
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: '${namePrefix}-jumpbox'
      adminUsername: adminUsername
      customData: base64(jumpboxCloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [
        { id: jumpboxNic.id }
      ]
    }
  }
}

// ---------------------------------------------------------------------------
// Private Endpoint connecting consumer VNet -> provider's Private Link Service.
// Auto-approved because the provider's PLS lists this subscription in
// autoApproval.subscriptions.
// ---------------------------------------------------------------------------
resource pe 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: peName
  location: location
  properties: {
    subnet: { id: peSubnet.id }
    privateLinkServiceConnections: [
      {
        name: 'pls-connection'
        properties: {
          privateLinkServiceId: privateLinkServiceId
          // No groupIds for PLS-backed PEs (only required for PaaS PEs).
          requestMessage: 'Consumer VNet requesting access to provider service.'
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Custom Private DNS zone for the provider service
// ---------------------------------------------------------------------------
// PLS-backed Private Endpoints do NOT come with a Microsoft-published
// `privatelink.*` zone (those exist only for 1st-party PaaS services).
// In production you bring your own zone — typically a sub-domain of your
// internal DNS namespace — and add an A record pointing at the PE's IP.
//
// We create the zone + VNet link here; deploy.sh creates the A record
// post-deployment once Azure has assigned the PE NIC its private IP.
resource providerDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: providerDnsZoneName
  location: 'global'
}

resource providerDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: providerDnsZone
  name: '${namePrefix}-consumer-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: vnet.id }
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output vnetName string = vnet.name
output vnetId string = vnet.id
output peSubnetId string = peSubnet.id
output jumpboxPublicIp string = jumpboxPip.properties.ipAddress
output privateEndpointName string = pe.name
output providerDnsZoneName string = providerDnsZone.name
output providerHostname string = providerHostname
output providerFqdn string = '${providerHostname}.${providerDnsZoneName}'
