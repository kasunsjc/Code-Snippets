// ========================================
// Main Bicep Template for Falco AKS Demo
// ========================================

targetScope = 'resourceGroup'

@description('The name of the AKS cluster')
param aksClusterName string = 'aks-falco-demo'

@description('The location for all resources')
param location string = resourceGroup().location

@description('The name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string = 'law-falco-demo'

@description('Enable Azure Sentinel on the Log Analytics workspace')
param enableSentinel bool = true

@description('The Kubernetes version')
param kubernetesVersion string = '1.33'

@description('The VM size for AKS nodes')
param nodeVmSize string = 'Standard_DS2_v2'

@description('The number of nodes in the AKS cluster')
param nodeCount int = 3

@description('The Azure AD user or group object ID to grant AKS RBAC Cluster Admin role')
param aksAdminPrincipalId string

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'Demo'
  Purpose: 'Falco-Security-Audit'
  ManagedBy: 'Bicep'
}

// ========================================
// Log Analytics Workspace
// ========================================
module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'deploy-log-analytics'
  params: {
    workspaceName: logAnalyticsWorkspaceName
    location: location
    retentionInDays: 30
    enableSentinel: enableSentinel
    tags: tags
  }
}

// ========================================
// AKS Cluster
// ========================================
module aksCluster 'modules/aks-cluster.bicep' = {
  name: 'deploy-aks-cluster'
  params: {
    clusterName: aksClusterName
    location: location
    kubernetesVersion: kubernetesVersion
    nodeVmSize: nodeVmSize
    nodeCount: nodeCount
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    aksAdminPrincipalId: aksAdminPrincipalId
    tags: tags
  }
}

// ========================================
// Logic App for Falco Webhook
// ========================================
module logicApp 'modules/logic-app.bicep' = {
  name: 'deploy-logic-app'
  params: {
    logicAppName: 'logic-falco-webhook'
    location: location
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    workspaceCustomerId: logAnalytics.outputs.workspaceCustomerId
    tags: tags
  }
}

// ========================================
// Outputs
// ========================================

@description('The resource ID of the AKS cluster')
output aksClusterResourceId string = aksCluster.outputs.clusterResourceId

@description('The name of the AKS cluster')
output aksClusterName string = aksCluster.outputs.clusterName

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalytics.outputs.workspaceName

@description('The Log Analytics workspace customer ID')
output workspaceCustomerId string = logAnalytics.outputs.workspaceCustomerId

@description('Sentinel deployment status')
output sentinelEnabled bool = enableSentinel

@description('AKS cluster FQDN')
output aksClusterFqdn string = aksCluster.outputs.clusterFqdn

@description('Logic App resource ID (use `az logic workflow show-callback-url` to fetch the webhook URL securely at deploy time)')
output logicAppId string = logicApp.outputs.logicAppId

@description('Logic App workflow name')
output logicAppName string = logicApp.outputs.logicAppName

@description('Logic App HTTP trigger name')
output logicAppTriggerName string = logicApp.outputs.logicAppTriggerName
