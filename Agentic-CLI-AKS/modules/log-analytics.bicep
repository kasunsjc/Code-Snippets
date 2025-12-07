// Log Analytics Workspace Module

@description('Name of the Log Analytics workspace')
param workspaceName string

@description('Location for the workspace')
param location string

@description('Tags for the workspace')
param tags object

@description('SKU for the workspace')
@allowed([
  'Free'
  'Standard'
  'Premium'
  'PerNode'
  'PerGB2018'
  'Standalone'
])
param sku string = 'PerGB2018'

@description('Retention in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

// Log Analytics Workspace
resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
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
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Container Insights Solution
resource containerInsights 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'ContainerInsights(${workspace.name})'
  location: location
  tags: tags
  properties: {
    workspaceResourceId: workspace.id
  }
  plan: {
    name: 'ContainerInsights(${workspace.name})'
    product: 'OMSGallery/ContainerInsights'
    promotionCode: ''
    publisher: 'Microsoft'
  }
}

// Outputs
output workspaceId string = workspace.id
output workspaceName string = workspace.name
output customerId string = workspace.properties.customerId
