// Azure Kubernetes Application Network Demo - Main Deployment
// Deploys an AKS cluster configured to join an Azure Kubernetes Application Network
// Requirements: OIDC issuer, AKS-managed Entra ID, Managed Gateway API enabled
// NOTE: Istio service mesh add-on must NOT be enabled on member clusters

targetScope = 'subscription'

@description('Azure region for all resources')
param location string = 'eastus'

@description('Environment name for resource naming')
param environmentName string = 'demo'

@description('AKS resource group name')
param aksResourceGroupName string = 'rg-appnet-${environmentName}'

@description('AppNet resource group name')
param appNetResourceGroupName string = 'rg-appnet-resource-${environmentName}'

@description('AKS cluster name')
param clusterName string = 'aks-appnet-${environmentName}'

@description('Kubernetes version')
param kubernetesVersion string = '1.32'

@description('System node pool VM size')
param systemNodeVmSize string = 'Standard_D2s_v3'

@description('System node pool initial node count')
param systemNodeCount int = 2

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'Demo'
  Project: 'AKS-Application-Network'
  ManagedBy: 'Bicep'
}

// Variables
var nodeResourceGroupName = 'rg-appnet-${environmentName}-nodes'
var logAnalyticsWorkspaceName = 'law-appnet-${environmentName}-${uniqueString(subscription().subscriptionId, aksResourceGroupName)}'

// AKS Resource Group
resource aksRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: aksResourceGroupName
  location: location
  tags: tags
}

// AppNet Resource Group
resource appNetRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: appNetResourceGroupName
  location: location
  tags: tags
}

// Log Analytics Workspace (for AKS monitoring)
module logAnalytics 'modules/log-analytics.bicep' = {
  scope: aksRg
  name: 'log-analytics-deployment'
  params: {
    workspaceName: logAnalyticsWorkspaceName
    location: location
    tags: tags
  }
}

// AKS Cluster
module aksCluster 'modules/aks.bicep' = {
  scope: aksRg
  name: 'aks-cluster-deployment'
  params: {
    clusterName: clusterName
    location: location
    kubernetesVersion: kubernetesVersion
    nodeResourceGroupName: nodeResourceGroupName
    systemNodeVmSize: systemNodeVmSize
    systemNodeCount: systemNodeCount
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: tags
  }
}

// Outputs
output aksResourceGroupName string = aksRg.name
output appNetResourceGroupName string = appNetRg.name
output clusterName string = aksCluster.outputs.clusterName
output clusterOidcIssuerUrl string = aksCluster.outputs.oidcIssuerUrl
