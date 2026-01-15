// Azure Monitor Associations with AKS
param aksClusterName string
param dataCollectionRuleId string
param grafanaPrincipalId string

// Get AKS cluster reference
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-02-01' existing = {
  name: aksClusterName
}

// Monitoring Reader role definition for AKS
var monitoringReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05')

// Assign Monitoring Reader role to Grafana on AKS cluster
resource grafanaAksMonitoringReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, grafanaPrincipalId, monitoringReaderRoleId)
  scope: aksCluster
  properties: {
    roleDefinitionId: monitoringReaderRoleId
    principalId: grafanaPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Data Collection Rule Association with AKS
resource dataCollectionRuleAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'aks-prometheus-association'
  scope: aksCluster
  properties: {
    dataCollectionRuleId: dataCollectionRuleId
    description: 'Association between AKS cluster and Prometheus DCR'
  }
}

output associationName string = dataCollectionRuleAssociation.name
