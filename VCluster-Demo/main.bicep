// Main Bicep template for vcluster Demo Host Cluster
// Deploys an AKS cluster optimised to host multiple virtual clusters

targetScope = 'resourceGroup'

@description('The Azure region for all resources')
param location string = resourceGroup().location

@description('Name prefix for all resources')
@minLength(3)
@maxLength(10)
param namePrefix string = 'vcluster'

@description('Environment name')
@allowed([
  'dev'
  'demo'
  'test'
])
param environment string = 'demo'

@description('Kubernetes version for the host AKS cluster')
param kubernetesVersion string = '1.31'

@description('System node pool VM size')
param systemNodeVmSize string = 'Standard_D2s_v3'

@description('System node pool count')
@minValue(1)
@maxValue(3)
param systemNodeCount int = 2

@description('User node pool VM size - should be large enough to host multiple vclusters')
param userNodeVmSize string = 'Standard_D4s_v3'

@description('User node pool count')
@minValue(2)
@maxValue(10)
param userNodeCount int = 3

@description('Enable Azure Monitor Container Insights')
param enableMonitoring bool = true

@description('Tags applied to all resources')
param tags object = {
  Environment: environment
  Project: 'VCluster-Demo'
  ManagedBy: 'Bicep'
}

// --------------------------------------------------
// Variables
// --------------------------------------------------
var aksClusterName    = '${namePrefix}-aks-${environment}'
var logAnalyticsName  = '${namePrefix}-logs-${environment}'
var vnetName          = '${namePrefix}-vnet-${environment}'
var nodeRgName        = 'rg-${namePrefix}-${environment}-nodes'

// --------------------------------------------------
// Log Analytics Workspace
// --------------------------------------------------
module logAnalytics 'modules/log-analytics.bicep' = if (enableMonitoring) {
  name: 'log-analytics-deployment'
  params: {
    workspaceName: logAnalyticsName
    location: location
    tags: tags
  }
}

// --------------------------------------------------
// Virtual Network
// --------------------------------------------------
module vnet 'modules/vnet.bicep' = {
  name: 'vnet-deployment'
  params: {
    vnetName: vnetName
    location: location
    tags: tags
  }
}

// --------------------------------------------------
// AKS Host Cluster
// --------------------------------------------------
module aks 'modules/aks.bicep' = {
  name: 'aks-deployment'
  params: {
    clusterName: aksClusterName
    location: location
    kubernetesVersion: kubernetesVersion
    systemNodeVmSize: systemNodeVmSize
    systemNodeCount: systemNodeCount
    userNodeVmSize: userNodeVmSize
    userNodeCount: userNodeCount
    vnetSubnetId: vnet.outputs.aksSubnetId
    logAnalyticsWorkspaceId: enableMonitoring ? logAnalytics.outputs.workspaceId : ''
    enableMonitoring: enableMonitoring
    nodeResourceGroup: nodeRgName
    tags: tags
  }
}

// --------------------------------------------------
// Outputs
// --------------------------------------------------
output aksClusterName string = aks.outputs.clusterName
output aksClusterFqdn string  = aks.outputs.clusterFqdn
output aksNodeResourceGroup string = nodeRgName
output vnetId string = vnet.outputs.vnetId
output logAnalyticsWorkspaceId string = enableMonitoring ? logAnalytics.outputs.workspaceId : ''
