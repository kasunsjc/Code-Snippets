//TODO: Fix the If condition for the outboundType in the AKS module

targetScope = 'subscription'

@description('Location of the Azure region to deploy the resources')
param location string = 'northeurope'

@description('Prefix for the resources')
param prefix string = 'aks'

@description('Address prefix for the virtual network')
param addressPrefix array = []

@description('Address prefix for the AKS subnet')
param aksSubnetPrefix string

@description('Kubernetes Version')
param kubeVersion string = '1.30.0'

@description('Network Profile e.g. azure, kubenet')
param networkProfile string = 'azure'

@description('Network Plugin Mode e.g. overlay')
param networkPluginMode string = 'overlay'

@description('Enable Managed NAT Gateway')
param enableManagedNatGateway bool = false

@description('Condition to check if the user defined NAT Gateway is enabled')
param userDefineNATGateway bool = false

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${prefix}-gateway-rg'
  location: location
}

module vnet './modules/vnet.bicep' = if (enableManagedNatGateway == false) {
  scope: resourceGroup
  name: 'aks-egress-vnet'
  params: {
    prefix: prefix
    location: location
    addressPrefix: addressPrefix
    aksSubnetPrefix: aksSubnetPrefix
    userDefineNATGateway: userDefineNATGateway
    natGatewayId: natGateway.outputs.natGatewayId
  }
}

module aks './modules/aks.bicep' = {
  scope: resourceGroup
  name: 'aks-egress'
  params: {
    prefix: prefix
    location: location
    kubeVersion: kubeVersion
    networkProfile: networkProfile
    networkPluginMode: networkPluginMode
    aksSubnetId: vnet.outputs.aksSubnetId
    enableManagedNatGateway: enableManagedNatGateway
    userDefineNATGateway: userDefineNATGateway
  }
}

module publicIpRange './modules/publicIpRange.bicep' = if ( userDefineNATGateway == true) {
  scope: resourceGroup
  name: 'aks-egress-public-ip-range'
  params: {
    prefix: prefix
    location: location
  }
}

module natGateway './modules/natGateway.bicep' = if ( userDefineNATGateway == true) {
  scope: resourceGroup
  name: 'aks-egress-nat-gateway'
  params: {
    prefix: prefix
    location: location
    publicIpRangeId: publicIpRange.outputs.publicIpRangeId
  }
}
