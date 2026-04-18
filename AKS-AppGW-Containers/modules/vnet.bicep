// Virtual Network Module for AKS with Application Gateway for Containers
// Includes AKS subnet and a delegated subnet for ALB association

@description('Name of the virtual network')
param vnetName string

@description('Location for the virtual network')
param location string

@description('Tags for the virtual network')
param tags object

@description('VNet address space')
param vnetAddressPrefix string = '10.0.0.0/8'

@description('AKS nodes subnet address prefix')
param aksSubnetPrefix string = '10.224.0.0/16'

@description('Application Gateway for Containers association subnet prefix (min /24 with 250+ IPs)')
param albSubnetPrefix string = '10.225.0.0/24'

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
        name: 'subnet-alb'
        properties: {
          addressPrefix: albSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.ServiceNetworking.trafficControllers'
              properties: {
                serviceName: 'Microsoft.ServiceNetworking/trafficControllers'
              }
            }
          ]
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output aksSubnetId string = vnet.properties.subnets[0].id
output albSubnetId string = vnet.properties.subnets[1].id
output albSubnetName string = vnet.properties.subnets[1].name
