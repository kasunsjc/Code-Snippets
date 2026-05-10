// ============================================================
// AKS KEDA Demo - Infrastructure Deployment
//
// Module-based Bicep orchestrator. Deploys:
//   - Log Analytics Workspace
//   - Azure Managed Prometheus + Managed Grafana (monitoring)
//   - AKS cluster with KEDA add-on + Azure Monitor profile
//   - Data Collection Rule Association (routes metrics to Prometheus)
//   - Prometheus Recording Rule Groups (powers Grafana dashboards)
//   - Azure Storage Account + Queue    (Scenario 01)
//   - Azure Service Bus Namespace + Queue  (Scenario 02)
//
// Scenarios covered:
//   01 - Azure Storage Queue scaler
//   02 - Azure Service Bus Queue scaler
//   03 - Cron (time-based) scaler
//   04 - Prometheus scaler (Azure Managed Prometheus)
//   05 - CPU / Memory scaler
// ============================================================

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Name of the AKS cluster.')
param clusterName string = 'aks-keda-demo'

@description('Kubernetes version.')
param kubernetesVersion string = '1.31'

@description('Number of nodes in the default system node pool.')
param nodeCount int = 2

@description('VM size for agent nodes.')
param nodeVmSize string = 'Standard_DS2_v2'

@description('Entra ID Object ID of the operator. Grants Grafana Admin and AKS RBAC Cluster Admin. Leave empty to skip.')
param userId string = ''

@description('Tags applied to all resources.')
param tags object = {
  Environment: 'Demo'
  Project: 'AKS-KEDA'
  ManagedBy: 'Bicep'
}

// ============================================================
// Variables
// ============================================================

var storageAccountName = take(replace(toLower('st${clusterName}keda'), '-', ''), 24)
var serviceBusNamespaceName = '${clusterName}-sb'
var nodeResourceGroupName = 'rg-${clusterName}-nodes'

// ============================================================
// Module: Log Analytics Workspace
// ============================================================

module logAnalytics './modules/log-analytics.bicep' = {
  name: 'log-analytics'
  params: {
    workspaceName: '${clusterName}-law'
    location: location
    tags: tags
  }
}

// ============================================================
// Module: Azure Managed Prometheus + Managed Grafana
// ============================================================

module monitoring './modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    baseName: clusterName
    location: location
    userId: userId
    tags: tags
  }
}

// ============================================================
// Module: AKS Cluster with KEDA Add-on
// ============================================================

module aks './modules/aks.bicep' = {
  name: 'aks'
  params: {
    clusterName: clusterName
    location: location
    kubernetesVersion: kubernetesVersion
    nodeCount: nodeCount
    nodeVmSize: nodeVmSize
    nodeResourceGroupName: nodeResourceGroupName
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    userId: userId
    tags: tags
  }
}

// ============================================================
// Module: DCR Association (AKS → Prometheus workspace)
// ============================================================

module dcrAssociation './modules/dcr-association.bicep' = {
  name: 'dcr-association'
  params: {
    aksClusterId: aks.outputs.aksClusterId
    dataCollectionRuleId: monitoring.outputs.dataCollectionRuleId
  }
}

// ============================================================
// Module: Prometheus Recording Rule Groups
// Powers the Azure Managed Grafana dashboards
// ============================================================

module recordingRules './modules/recording-rules.bicep' = {
  name: 'recording-rules'
  params: {
    location: location
    clusterName: clusterName
    prometheusWorkspaceId: monitoring.outputs.prometheusWorkspaceId
    aksClusterId: aks.outputs.aksClusterId
  }
}

// ============================================================
// Module: Azure Storage Account + Queue  (Scenario 01)
// ============================================================

module storage './modules/storage.bicep' = {
  name: 'storage'
  params: {
    storageAccountName: storageAccountName
    location: location
    tags: tags
  }
}

// ============================================================
// Module: Azure Service Bus Namespace + Queue  (Scenario 02)
// ============================================================

module serviceBus './modules/servicebus.bicep' = {
  name: 'servicebus'
  params: {
    namespaceName: serviceBusNamespaceName
    location: location
    tags: tags
  }
}

// ============================================================
// Outputs
// ============================================================

output aksClusterName string = aks.outputs.aksClusterName
output nodeResourceGroup string = nodeResourceGroupName
output oidcIssuerUrl string = aks.outputs.oidcIssuerUrl
output storageAccountName string = storage.outputs.storageAccountName
output storageQueueName string = storage.outputs.storageQueueName
output serviceBusNamespaceName string = serviceBus.outputs.namespaceName
output serviceBusQueueName string = serviceBus.outputs.queueName
output prometheusQueryEndpoint string = monitoring.outputs.prometheusQueryEndpoint
output grafanaUrl string = monitoring.outputs.grafanaUrl
