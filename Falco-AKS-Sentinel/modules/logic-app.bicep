// ========================================
// Logic App Module for Falco Webhook
// ========================================

@description('The name of the Logic App')
param logicAppName string

@description('The location for the Logic App')
param location string

@description('Log Analytics workspace resource ID')
param logAnalyticsWorkspaceId string

@description('Log Analytics workspace customer ID')
param workspaceCustomerId string

@description('Resource tags')
param tags object = {}

// Extract workspace name from resource ID
var workspaceNameFromId = last(split(logAnalyticsWorkspaceId, '/'))
var workspaceResourceGroup = split(logAnalyticsWorkspaceId, '/')[4]

// Reference to existing Log Analytics workspace for keys
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: workspaceNameFromId
  scope: resourceGroup(workspaceResourceGroup)
}

// ========================================
// API Connection for Log Analytics Data Collector
// ========================================
resource logAnalyticsConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'azureloganalyticsdatacollector-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  properties: {
    displayName: 'Log Analytics Data Collector'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureloganalyticsdatacollector')
    }
    parameterValues: {
      username: workspaceCustomerId
      password: logAnalyticsWorkspace.listKeys().primarySharedKey
    }
  }
}

// ========================================
// Logic App
// ========================================
resource logicApp 'Microsoft.Logic/workflows@2017-07-01' = {
  name: logicAppName
  location: location
  tags: tags
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        When_an_HTTP_request_is_received: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            method: 'POST'
          }
        }
      }
      actions: {
        Send_Data: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: '@{triggerBody()}'
            headers: {
              'Log-Type': 'FalcoLogs'
            }
            path: '/api/logs'
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azureloganalyticsdatacollector: {
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureloganalyticsdatacollector')
            connectionId: logAnalyticsConnection.id
            connectionName: 'azureloganalyticsdatacollector'
            connectionProperties: {}
          }
        }
      }
    }
  }
}

// ========================================
// Outputs
// ========================================

@description('The resource ID of the Logic App')
output logicAppId string = logicApp.id

@description('The name of the Logic App')
output logicAppName string = logicApp.name

@description('The name of the trigger to use with `az logic workflow show-callback-url`.')
output logicAppTriggerName string = 'When_an_HTTP_request_is_received'

// NOTE: The callback URL is intentionally NOT exported as a Bicep output.
// It contains a SAS signature that grants invocation rights to the workflow,
// and Bicep outputs are persisted in deployment history. The deployment scripts
// retrieve it at runtime via `az logic workflow show-callback-url` instead.
