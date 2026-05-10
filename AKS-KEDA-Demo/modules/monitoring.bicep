// ============================================================
// Module: Azure Managed Prometheus + Managed Grafana
//
// Creates:
//   - Azure Monitor Workspace (Managed Prometheus)
//   - Azure Managed Grafana (Standard tier)
//   - Data Collection Endpoint (DCE)
//   - Data Collection Rule (DCR) — routes Prometheus metrics to the workspace
//   - Role assignments: Grafana → Prometheus (Monitoring Reader + Data Reader)
// ============================================================

@description('Base name used for all monitoring resources.')
param baseName string

@description('Azure region.')
param location string

@description('Object ID of the user to assign the Grafana Admin role. Leave empty to skip.')
param userId string = ''

@description('Resource tags.')
param tags object = {}

// ============================================================
// Azure Monitor Workspace (Managed Prometheus)
// ============================================================

resource prometheusWorkspace 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: '${baseName}-prometheus'
  location: location
  tags: tags
}

// ============================================================
// Azure Managed Grafana
// ============================================================

var grafanaName = length('${baseName}-grafana') > 23
  ? take(replace(baseName, '-', ''), 23)
  : '${baseName}-grafana'

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
          azureMonitorWorkspaceResourceId: prometheusWorkspace.id
        }
      ]
    }
    publicNetworkAccess: 'Enabled'
  }
}

// ============================================================
// Data Collection Endpoint (DCE)
// ============================================================

resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = {
  name: 'MSProm-${location}-${baseName}'
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// ============================================================
// Data Collection Rule (DCR)
// Routes Prometheus metrics from AKS → Azure Monitor Workspace
// ============================================================

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'MSProm-${location}-${baseName}'
  location: location
  tags: tags
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
          accountResourceId: prometheusWorkspace.id
          name: 'MonitoringAccount1'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-PrometheusMetrics'
        ]
        destinations: [
          'MonitoringAccount1'
        ]
      }
    ]
  }
}

// ============================================================
// Role Assignments: Grafana → Prometheus workspace
// ============================================================

// Monitoring Reader — allows Grafana to list workspaces
resource monitoringReaderRoleDef 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
  scope: subscription()
}

// Monitoring Data Reader — allows Grafana to query metrics
resource monitoringDataReaderRoleDef 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'b0d8363b-8ddd-447d-831f-62ca05bff136'
  scope: subscription()
}

resource grafanaMonitoringReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(baseName, prometheusWorkspace.name, monitoringReaderRoleDef.id)
  scope: prometheusWorkspace
  properties: {
    roleDefinitionId: monitoringReaderRoleDef.id
    principalId: grafana.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource grafanaMonitoringDataReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(baseName, prometheusWorkspace.name, monitoringDataReaderRoleDef.id)
  scope: prometheusWorkspace
  properties: {
    roleDefinitionId: monitoringDataReaderRoleDef.id
    principalId: grafana.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================
// Optional: Grafana Admin role for a specific user
// ============================================================

resource grafanaAdminRoleDef 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '22926164-76b3-42b3-bc55-97df8dab3e41'
  scope: subscription()
}

resource userGrafanaAdminAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(userId)) {
  name: guid(baseName, userId, grafanaAdminRoleDef.id)
  scope: grafana
  properties: {
    roleDefinitionId: grafanaAdminRoleDef.id
    principalId: userId
    principalType: 'User'
  }
}

// ============================================================
// Outputs
// ============================================================

output prometheusWorkspaceId string = prometheusWorkspace.id
output prometheusQueryEndpoint string = prometheusWorkspace.properties.metrics.prometheusQueryEndpoint
output grafanaUrl string = grafana.properties.endpoint
output grafanaPrincipalId string = grafana.identity.principalId
output dataCollectionRuleId string = dataCollectionRule.id
