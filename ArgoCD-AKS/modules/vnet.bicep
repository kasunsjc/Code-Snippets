@description('The location for the Virtual Network')
param location string

@description('The base name for resources')
param baseName string

@description('The environment name')
param environmentName string

@description('Tags to apply to resources')
param tags object

@description('Virtual Network address prefix')
param vnetAddressPrefix string

@description('AKS subnet address prefix')
param aksSubnetAddressPrefix string

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-${baseName}-${environmentName}'
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
        name: 'snet-aks'
        properties: {
          addressPrefix: aksSubnetAddressPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output aksSubnetId string = vnet.properties.subnets[0].id
output aksSubnetName string = vnet.properties.subnets[0].name
