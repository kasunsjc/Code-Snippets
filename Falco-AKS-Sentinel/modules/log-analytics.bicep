// ========================================
// Log Analytics Workspace Module
// ========================================

@description('The name of the Log Analytics workspace')
param workspaceName string

@description('The location for the workspace')
param location string

@description('The retention period in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Enable Azure Sentinel')
param enableSentinel bool = true

@description('Resource tags')
param tags object = {}

// ========================================
// Log Analytics Workspace
// ========================================
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
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ========================================
// Azure Sentinel (SecurityInsights Solution)
// ========================================
resource sentinelSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = if (enableSentinel) {
  name: 'SecurityInsights(${workspaceName})'
  location: location
  tags: tags
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
  plan: {
    name: 'SecurityInsights(${workspaceName})'
    product: 'OMSGallery/SecurityInsights'
    publisher: 'Microsoft'
    promotionCode: ''
  }
}

// Onboard workspace to Sentinel
resource sentinelOnboarding 'Microsoft.SecurityInsights/onboardingStates@2024-03-01' = if (enableSentinel) {
  scope: logAnalyticsWorkspace
  name: 'default'
  properties: {}
  dependsOn: [
    sentinelSolution
  ]
}

// ========================================
// Custom Table for Falco Logs
// Note: Table will be auto-created by Data Collector API on first ingestion
// Auto-created tables don't count against the 10 custom table limit
// ========================================

// ========================================
// Outputs
// ========================================

@description('The resource ID of the Log Analytics workspace')
output workspaceId string = logAnalyticsWorkspace.id

@description('The name of the Log Analytics workspace')
output workspaceName string = logAnalyticsWorkspace.name

@description('The workspace customer ID (used for agents)')
output workspaceCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('The workspace primary shared key')
@secure()
output workspaceKey string = logAnalyticsWorkspace.listKeys().primarySharedKey
