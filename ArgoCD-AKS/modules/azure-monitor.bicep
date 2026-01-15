// Azure Monitor Workspace with Managed Prometheus and Grafana
param location string
param azureMonitorWorkspaceName string
param grafanaName string
param tags object = {}
param currentUserObjectId string = ''

// Azure Monitor Workspace (for Managed Prometheus)
resource azureMonitorWorkspace 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: azureMonitorWorkspaceName
  location: location
  tags: tags
  properties: {}
}

// Managed Grafana
resource grafana 'Microsoft.Dashboard/grafana@2023-09-01' = {
  name: grafanaName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    grafanaIntegrations: {
      azureMonitorWorkspaceIntegrations: [
        {
          azureMonitorWorkspaceResourceId: azureMonitorWorkspace.id
        }
      ]
    }
    zoneRedundancy: 'Disabled'
    publicNetworkAccess: 'Enabled'
    apiKey: 'Enabled'
    deterministicOutboundIP: 'Disabled'
  }
}

// Monitoring Data Reader role definition
var monitoringDataReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b0d8363b-8ddd-447d-831f-62ca05bff136')

// Assign Monitoring Data Reader role to Grafana on Azure Monitor Workspace
resource grafanaMonitoringDataReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(azureMonitorWorkspace.id, grafana.id, monitoringDataReaderRoleId)
  scope: azureMonitorWorkspace
  properties: {
    roleDefinitionId: monitoringDataReaderRoleId
    principalId: grafana.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grafana Admin role definition
var grafanaAdminRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '22926164-76b3-42b3-bc55-97df8dab3e41')

// Assign Grafana Admin role to current user (idempotent)
resource currentUserGrafanaAdminAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(currentUserObjectId)) {
  name: guid(grafana.id, currentUserObjectId, grafanaAdminRoleId, 'grafana-admin')
  scope: grafana
  properties: {
    roleDefinitionId: grafanaAdminRoleId
    principalId: currentUserObjectId
    principalType: 'User'
  }
}

// Data Collection Endpoint
resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: '${azureMonitorWorkspaceName}-dce'
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// Data Collection Rule for Prometheus
resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: '${azureMonitorWorkspaceName}-dcr'
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    dataCollectionEndpointId: dataCollectionEndpoint.id
    dataSources: {
      prometheusForwarder: [
        {
          name: 'PrometheusDataSource'
          streams: [
            'Microsoft-PrometheusMetrics'
          ]
          labelIncludeFilter: {}
        }
      ]
    }
    destinations: {
      monitoringAccounts: [
        {
          accountResourceId: azureMonitorWorkspace.id
          name: 'MonitoringAccount'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-PrometheusMetrics'
        ]
        destinations: [
          'MonitoringAccount'
        ]
      }
    ]
  }
}

output azureMonitorWorkspaceId string = azureMonitorWorkspace.id
output azureMonitorWorkspaceName string = azureMonitorWorkspace.name
output grafanaId string = grafana.id
output grafanaName string = grafana.name
output grafanaEndpoint string = grafana.properties.endpoint
output grafanaPrincipalId string = grafana.identity.principalId
output dataCollectionEndpointId string = dataCollectionEndpoint.id
output dataCollectionRuleId string = dataCollectionRule.id
