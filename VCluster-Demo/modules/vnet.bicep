// modules/vnet.bicep
// Virtual Network for the vcluster demo host AKS cluster

@description('Name of the Virtual Network')
param vnetName string

@description('Azure region')
param location string = resourceGroup().location

@description('Tags')
param tags object = {}

// 10.0.0.0/8 gives plenty of space for multiple vclusters
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/8'
      ]
    }
    subnets: [
      {
        name: 'aks-subnet'
        properties: {
          addressPrefix: '10.240.0.0/16'
          // Delegate to AKS
          delegations: []
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output aksSubnetId string = vnet.properties.subnets[0].id
output vnetName string = vnet.name
