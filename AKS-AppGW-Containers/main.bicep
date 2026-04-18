// Main Bicep template for AKS with Application Gateway for Containers
// Supports two deployment strategies:
//   - 'byo'     : Bring Your Own — AGFC resource, frontend, and association created in Azure via Bicep
//   - 'managed' : Managed by ALB Controller — lifecycle managed via ApplicationLoadBalancer CRD in Kubernetes

targetScope = 'resourceGroup'

@description('The Azure region for all resources')
param location string = resourceGroup().location

@description('The name prefix for all resources')
@minLength(3)
@maxLength(10)
param namePrefix string = 'agfc'

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

@description('Enable Azure Monitor Container Insights')
param enableMonitoring bool = true

@description('Deployment strategy: byo (Bring Your Own) or managed (ALB Controller managed)')
@allowed([
  'byo'
  'managed'
])
param deploymentStrategy string = 'managed'

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: 'AKS-AppGW-Containers'
  ManagedBy: 'Bicep'
}

// Variables
var aksClusterName = '${namePrefix}-aks-${environment}'
var logAnalyticsName = '${namePrefix}-logs-${environment}'
var vnetName = '${namePrefix}-vnet-${environment}'
var agfcName = '${namePrefix}-agfc-${environment}'

// Log Analytics Workspace
module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'log-analytics-deployment'
  params: {
    workspaceName: logAnalyticsName
    location: location
    tags: tags
  }
}

// Virtual Network with ALB delegated subnet
module vnet 'modules/vnet.bicep' = {
  name: 'vnet-deployment'
  params: {
    vnetName: vnetName
    location: location
    tags: tags
  }
}

// AKS Cluster with Azure CNI Overlay, OIDC, Workload Identity
module aks 'modules/aks.bicep' = {
  name: 'aks-deployment'
  params: {
    clusterName: aksClusterName
    location: location
    kubernetesVersion: kubernetesVersion
    systemNodeCount: systemNodeCount
    systemNodeVmSize: systemNodeVmSize
    subnetId: vnet.outputs.aksSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    enableMonitoring: enableMonitoring
    tags: tags
  }
}

// Application Gateway for Containers (BYO strategy only)
// For 'managed' strategy, the AGFC resource is created via ApplicationLoadBalancer CRD in Kubernetes
module agfc 'modules/agfc.bicep' = if (deploymentStrategy == 'byo') {
  name: 'agfc-deployment'
  params: {
    agfcName: agfcName
    location: location
    albSubnetId: vnet.outputs.albSubnetId
    tags: tags
  }
}

// Outputs
output aksClusterName string = aks.outputs.clusterName
output aksClusterFqdn string = aks.outputs.clusterFqdn
output nodeResourceGroup string = aks.outputs.nodeResourceGroup
output albSubnetId string = vnet.outputs.albSubnetId
output vnetName string = vnet.outputs.vnetName
output deploymentStrategy string = deploymentStrategy
output agfcName string = deploymentStrategy == 'byo' ? agfc.outputs.agfcName : 'managed-by-alb-controller'
output agfcId string = deploymentStrategy == 'byo' ? agfc.outputs.agfcId : ''
output frontendName string = deploymentStrategy == 'byo' ? agfc.outputs.frontendName : ''
