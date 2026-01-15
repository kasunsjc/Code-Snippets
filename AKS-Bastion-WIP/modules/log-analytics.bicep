targetScope = 'resourceGroup'

@description('Location for the workspace')
param location string

@description('Name of the Log Analytics workspace')
param workspaceName string

@description('SKU for the workspace')
param sku string = 'PerGB2018'

@description('Retention in days')
param retentionInDays int = 30

@description('Tags to apply to resources')
param tags object = {}

// Log Analytics Workspace
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
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

// Outputs
output workspaceId string = workspace.id
output workspaceName string = workspace.name
output customerId string = workspace.properties.customerId
