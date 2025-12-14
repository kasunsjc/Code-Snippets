// Virtual Network for AKS Cluster

@description('Name of the virtual network')
param vnetName string

@description('Location for the virtual network')
param location string

@description('Address prefix for the virtual network')
param addressPrefix string

@description('Address prefix for the AKS subnet')
param aksSubnetPrefix string

@description('Resource tags')
param tags object = {}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: 'aks-subnet'
        properties: {
          addressPrefix: aksSubnetPrefix
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output aksSubnetId string = vnet.properties.subnets[0].id
