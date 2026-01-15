targetScope = 'subscription'

@description('The location for all resources')
param location string

@description('The environment name (e.g., dev, prod)')
param environmentName string

@description('The base name for all resources')
param baseName string

@description('Tags to apply to all resources')
param tags object

@description('AKS configuration')
param aksConfig object

@description('Network configuration')
param networkConfig object

@description('Log Analytics configuration')
param logAnalyticsConfig object

@description('Current user object ID for Grafana access')
param currentUserObjectId string = ''

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-${baseName}-${environmentName}'
  location: location
  tags: tags
}

// Log Analytics Workspace
module logAnalytics './modules/log-analytics.bicep' = {
  name: 'log-analytics-deployment'
  scope: rg
  params: {
    location: location
    baseName: baseName
    environmentName: environmentName
    tags: tags
    retentionInDays: logAnalyticsConfig.retentionInDays
    sku: logAnalyticsConfig.sku
  }
}

// Virtual Network
module vnet './modules/vnet.bicep' = {
  name: 'vnet-deployment'
  scope: rg
  params: {
    location: location
    baseName: baseName
    environmentName: environmentName
    tags: tags
    vnetAddressPrefix: networkConfig.vnetAddressPrefix
    aksSubnetAddressPrefix: networkConfig.aksSubnetAddressPrefix
  }
}

// Azure Monitor Workspace (Managed Prometheus and Grafana) - Deploy first
module azureMonitor './modules/azure-monitor.bicep' = {
  name: 'azure-monitor-deployment'
  scope: rg
  params: {
    location: location
    azureMonitorWorkspaceName: 'amw-${baseName}-${environmentName}'
    grafanaName: 'grafana-${baseName}-${environmentName}'
    tags: tags
    currentUserObjectId: currentUserObjectId
  }
}

// AKS Cluster - Now can reference Azure Monitor workspace ID
module aks './modules/aks.bicep' = {
  name: 'aks-deployment'
  scope: rg
  params: {
    location: location
    baseName: baseName
    environmentName: environmentName
    tags: tags
    kubernetesVersion: aksConfig.kubernetesVersion
    nodeCount: aksConfig.nodeCount
    nodeVmSize: aksConfig.nodeVmSize
    maxPods: aksConfig.maxPods
    subnetId: vnet.outputs.aksSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    enableMonitoring: aksConfig.enableMonitoring
    networkPlugin: aksConfig.networkPlugin
    networkPolicy: aksConfig.networkPolicy
    azureMonitorWorkspaceId: azureMonitor.outputs.azureMonitorWorkspaceId
  }
}

// Azure Monitor Associations - Connect AKS with monitoring after both exist
module azureMonitorAssociations './modules/azure-monitor-associations.bicep' = {
  name: 'azure-monitor-associations-deployment'
  scope: rg
  params: {
    aksClusterName: aks.outputs.clusterName
    dataCollectionRuleId: azureMonitor.outputs.dataCollectionRuleId
    grafanaPrincipalId: azureMonitor.outputs.grafanaPrincipalId
  }
}

// Outputs
output resourceGroupName string = rg.name
output aksClusterName string = aks.outputs.clusterName
output aksClusterFqdn string = aks.outputs.clusterFqdn
output aksClusterId string = aks.outputs.clusterId
output vnetId string = vnet.outputs.vnetId
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output logAnalyticsWorkspaceName string = logAnalytics.outputs.workspaceName
output azureMonitorWorkspaceId string = azureMonitor.outputs.azureMonitorWorkspaceId
output azureMonitorWorkspaceName string = azureMonitor.outputs.azureMonitorWorkspaceName
output grafanaId string = azureMonitor.outputs.grafanaId
output grafanaName string = azureMonitor.outputs.grafanaName
output grafanaEndpoint string = azureMonitor.outputs.grafanaEndpoint
