targetScope = 'resourceGroup'

@description('Location for the resources')
param location string

@description('Virtual Network name')
param vnetName string

@description('Address prefix for the Virtual Network')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Address prefix for AKS subnet')
param aksSubnetPrefix string = '10.0.0.0/22'

@description('Address prefix for Azure Bastion subnet')
param bastionSubnetPrefix string = '10.0.4.0/26'

@description('Tags to apply to resources')
param tags object = {}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
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
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
    ]
  }
}

// Outputs
output vnetId string = vnet.id
output vnetName string = vnet.name
output aksSubnetId string = vnet.properties.subnets[0].id
output bastionSubnetId string = vnet.properties.subnets[1].id
