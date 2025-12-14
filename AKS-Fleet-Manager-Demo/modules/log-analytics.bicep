// Log Analytics Workspace

@description('Name of the Log Analytics Workspace')
param workspaceName string

@description('Location for the workspace')
param location string

@description('Workspace SKU')
param sku string = 'PerGB2018'

@description('Retention in days')
param retentionInDays int = 30

@description('Resource tags')
param tags object = {}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: sku
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
output workspaceCustomerId string = logAnalyticsWorkspace.properties.customerId
