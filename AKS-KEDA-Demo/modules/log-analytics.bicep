// ============================================================
// Module: Log Analytics Workspace
// ============================================================

@description('Name of the Log Analytics Workspace.')
param workspaceName string

@description('Azure region.')
param location string

@description('Data retention in days.')
param retentionInDays int = 30

@description('Resource tags.')
param tags object = {}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
