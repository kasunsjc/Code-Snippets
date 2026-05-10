// ============================================================
// Module: Data Collection Rule Association
//
// Associates an existing Data Collection Rule (DCR) with an
// AKS cluster so Prometheus metrics are forwarded to an
// Azure Monitor Workspace.
// ============================================================

@description('Resource ID of the AKS cluster to associate.')
param aksClusterId string

@description('Resource ID of the Data Collection Rule.')
param dataCollectionRuleId string

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: last(split(aksClusterId, '/'))!
  scope: resourceGroup()
}

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: 'MSProm-${last(split(aksClusterId, '/'))}'
  scope: aksCluster
  properties: {
    dataCollectionRuleId: dataCollectionRuleId
    description: 'Association of Data Collection Rule for Azure Managed Prometheus'
  }
}
