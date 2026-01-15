@description('The location for the Log Analytics workspace')
param location string

@description('The base name for resources')
param baseName string

@description('The environment name')
param environmentName string

@description('Tags to apply to resources')
param tags object

@description('Log Analytics retention in days')
param retentionInDays int = 30

@description('Log Analytics SKU')
param sku string = 'PerGB2018'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${baseName}-${environmentName}'
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
output customerId string = logAnalyticsWorkspace.properties.customerId
