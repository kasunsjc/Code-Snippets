targetScope = 'resourceGroup'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Name of the AKS cluster')
param aksClusterName string = 'aks-private-cluster'

@description('DNS prefix for the AKS cluster')
param dnsPrefix string = 'aksprivate'

@description('Kubernetes version')
param kubernetesVersion string = '1.29.0'

@description('VM size for AKS nodes')
param agentVMSize string = 'Standard_D2s_v3'

@description('Number of nodes in the AKS cluster')
param agentCount int = 2

@description('Name of the Virtual Network')
param vnetName string = 'vnet-aks-bastion'

@description('Name of the Bastion host')
param bastionName string = 'bastion-aks'

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'Demo'
  Purpose: 'AKS-Bastion-Demo'
}

// Deploy Log Analytics Workspace
module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'logAnalyticsDeploy'
  params: {
    location: location
    workspaceName: 'law-aks-${uniqueString(resourceGroup().id)}'
    tags: tags
  }
}

// Deploy Virtual Network
module vnet 'modules/vnet.bicep' = {
  name: 'vnetDeploy'
  params: {
    location: location
    vnetName: vnetName
    tags: tags
  }
}

// Deploy Azure Bastion
module bastion 'modules/bastion.bicep' = {
  name: 'bastionDeploy'
  params: {
    location: location
    bastionName: bastionName
    bastionSubnetId: vnet.outputs.bastionSubnetId
    tags: tags
  }
  dependsOn: [
    vnet
  ]
}

// Deploy Private AKS Cluster
module aks 'modules/aks.bicep' = {
  name: 'aksDeploy'
  params: {
    location: location
    clusterName: aksClusterName
    dnsPrefix: dnsPrefix
    kubernetesVersion: kubernetesVersion
    agentCount: agentCount
    agentVMSize: agentVMSize
    subnetId: vnet.outputs.aksSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: tags
  }
  dependsOn: [
    vnet
    logAnalytics
  ]
}

// Outputs
output aksClusterName string = aks.outputs.clusterName
output aksClusterFqdn string = aks.outputs.controlPlaneFQDN
output bastionName string = bastion.outputs.bastionName
output bastionResourceId string = bastion.outputs.bastionId
output vnetName string = vnet.outputs.vnetName
output resourceGroupName string = resourceGroup().name
