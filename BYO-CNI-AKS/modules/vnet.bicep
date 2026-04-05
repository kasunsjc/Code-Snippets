// Virtual Network Module for BYO CNI AKS with Cilium
// Uses a large subnet to accommodate Cilium's IPAM requirements

@description('Name of the virtual network')
param vnetName string

@description('Location for the virtual network')
param location string

@description('Tags for the virtual network')
param tags object

@description('VNet address space')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('AKS nodes subnet address prefix - sized large for Cilium pod CIDR')
param aksSubnetPrefix string = '10.0.0.0/16'

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'aks-subnet'
        properties: {
          addressPrefix: aksSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

// Outputs
output vnetId string = vnet.id
output vnetName string = vnet.name
output aksSubnetId string = vnet.properties.subnets[0].id
