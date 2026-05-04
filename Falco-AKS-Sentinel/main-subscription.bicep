// ========================================
// Subscription-Level Bicep Template for Falco AKS Demo
// This creates the resource group and deploys all resources
// ========================================

targetScope = 'subscription'

@description('The name of the resource group to create')
param resourceGroupName string = 'rg-falco-demo'

@description('The location for the resource group and all resources')
param location string = 'eastus'

@description('The name of the AKS cluster')
param aksClusterName string = 'aks-falco-demo'

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
// Resource Group
// ========================================
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ========================================
// Deploy Resources into Resource Group
// ========================================
module resources 'main.bicep' = {
  name: 'deploy-resources'
  scope: rg
  params: {
    aksClusterName: aksClusterName
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    enableSentinel: enableSentinel
    kubernetesVersion: kubernetesVersion
    nodeVmSize: nodeVmSize
    nodeCount: nodeCount
    aksAdminPrincipalId: aksAdminPrincipalId
    tags: tags
  }
}

// ========================================
// Outputs
// ========================================

@description('The name of the resource group')
output resourceGroupName string = rg.name

@description('The resource ID of the AKS cluster')
output aksClusterResourceId string = resources.outputs.aksClusterResourceId

@description('The name of the AKS cluster')
output aksClusterName string = resources.outputs.aksClusterName

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = resources.outputs.logAnalyticsWorkspaceId

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = resources.outputs.logAnalyticsWorkspaceName

@description('The Log Analytics workspace customer ID')
output workspaceCustomerId string = resources.outputs.workspaceCustomerId

@description('Sentinel deployment status')
output sentinelEnabled bool = resources.outputs.sentinelEnabled

@description('AKS cluster FQDN')
output aksClusterFqdn string = resources.outputs.aksClusterFqdn

@description('Logic App webhook URL')
output logicAppWebhookUrl string = resources.outputs.logicAppWebhookUrl

@description('Logic App resource ID')
output logicAppId string = resources.outputs.logicAppId
