// Virtual Network Module

@description('Name of the virtual network')
param vnetName string

@description('Location for the virtual network')
param location string

@description('Tags for the virtual network')
param tags object

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'aks-subnet'
        properties: {
          addressPrefix: '10.0.0.0/20'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'services-subnet'
        properties: {
          addressPrefix: '10.0.16.0/24'
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
output servicesSubnetId string = vnet.properties.subnets[1].id
