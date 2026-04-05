// Main Bicep template for BYO CNI AKS with Cilium Demo
// Deploys AKS cluster with networkPlugin 'none' for Cilium CNI

targetScope = 'resourceGroup'

@description('The Azure region for all resources')
param location string = resourceGroup().location

@description('The name prefix for all resources')
@minLength(3)
@maxLength(10)
param namePrefix string = 'byocni'

@description('Environment name (dev, test, prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('AKS Kubernetes version')
param kubernetesVersion string = '1.31.2'

@description('System node pool count')
@minValue(1)
@maxValue(5)
param systemNodeCount int = 2

@description('System node pool VM size')
param systemNodeVmSize string = 'Standard_D2s_v3'

@description('User node pool count')
@minValue(1)
@maxValue(10)
param userNodeCount int = 2

@description('User node pool VM size')
param userNodeVmSize string = 'Standard_D4s_v3'

@description('Enable Azure Monitor Container Insights')
param enableMonitoring bool = true

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: 'BYO-CNI-AKS-Cilium'
  ManagedBy: 'Bicep'
}

// Variables
var aksClusterName = '${namePrefix}-aks-${environment}'
var logAnalyticsName = '${namePrefix}-logs-${environment}'
var vnetName = '${namePrefix}-vnet-${environment}'

// Log Analytics Workspace
module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'log-analytics-deployment'
  params: {
    workspaceName: logAnalyticsName
    location: location
    tags: tags
  }
}

// Virtual Network
module vnet 'modules/vnet.bicep' = {
  name: 'vnet-deployment'
  params: {
    vnetName: vnetName
    location: location
    tags: tags
  }
}

// AKS Cluster with BYO CNI
module aks 'modules/aks.bicep' = {
  name: 'aks-deployment'
  params: {
    clusterName: aksClusterName
    location: location
    kubernetesVersion: kubernetesVersion
    systemNodeCount: systemNodeCount
    systemNodeVmSize: systemNodeVmSize
    userNodeCount: userNodeCount
    userNodeVmSize: userNodeVmSize
    subnetId: vnet.outputs.aksSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    enableMonitoring: enableMonitoring
    tags: tags
  }
}

// Outputs
output aksClusterName string = aks.outputs.clusterName
output aksClusterFqdn string = aks.outputs.clusterFqdn
output aksResourceId string = aks.outputs.aksResourceId
output resourceGroupName string = resourceGroup().name
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output vnetName string = vnet.outputs.vnetName
