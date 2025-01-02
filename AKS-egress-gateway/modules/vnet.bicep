@description('prefix for the resources')
param prefix string

@description('Location of the Azure region to deploy the resources')
param location string = 'northeurope'

@description('Address prefix for the virtual network')
param addressPrefix array = []

@description('Address prefix for the AKS subnet')
param aksSubnetPrefix string

@description('Nat Gateway ID')
param natGatewayId string

@description('Condition to check if the user defined NAT Gateway is enabled')
param userDefineNATGateway bool = false

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2020-11-01' = {
  name: '${prefix}-gateway-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: addressPrefix
    }
  }
}

resource aksSubnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' = {
  name: '${prefix}-subnet'
  parent: virtualNetwork
  properties: {
    addressPrefix: aksSubnetPrefix
    natGateway: {
      id: userDefineNATGateway == true ? natGatewayId : 'null'
    }
  }
}

output vnetId string = virtualNetwork.id
output aksSubnetId string = aksSubnet.id
