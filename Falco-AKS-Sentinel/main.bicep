// ============================================================
// Falco Runtime Security on AKS → Microsoft Sentinel
// ============================================================
// Deploys:
//   - Log Analytics workspace (Sentinel-enabled)
//   - Microsoft Sentinel onboarding
//   - Logic App (HTTP webhook → Log Analytics custom table)
//   - API connection for Azure Log Analytics Data Collector
//   - AKS cluster (small, dev-grade) with Container Insights
//   - Sentinel scheduled analytics rule for Falco alerts
// ============================================================

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Project / demo prefix used to derive resource names.')
@minLength(3)
@maxLength(12)
param projectName string = 'falcosec'

@description('Name of the AKS cluster.')
param clusterName string = '${projectName}-aks'

@description('Kubernetes version.')
param kubernetesVersion string = '1.30'

@description('Number of nodes in the system node pool.')
@minValue(1)
@maxValue(10)
param nodeCount int = 2

@description('VM size for the system node pool.')
param nodeVmSize string = 'Standard_DS2_v2'

@description('Log Analytics retention in days.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

var workspaceName = '${projectName}-law'
var logicAppName = '${projectName}-falco-ingest'
var laConnectionName = '${projectName}-la-connection'
var customLogTableName = 'FalcoAlerts_CL'
var nodeResourceGroup = 'rg-${projectName}-nodes'

// ============================================================
// Log Analytics Workspace
// ============================================================
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
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

// ============================================================
// Microsoft Sentinel onboarding (legacy solution alias works
// across all regions and is supported alongside the newer
// Microsoft.SecurityInsights/onboardingStates resource).
// ============================================================
resource sentinel 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'SecurityInsights(${workspace.name})'
  location: location
  properties: {
    workspaceResourceId: workspace.id
  }
  plan: {
    name: 'SecurityInsights(${workspace.name})'
    publisher: 'Microsoft'
    product: 'OMSGallery/SecurityInsights'
    promotionCode: ''
  }
}

// ============================================================
// API Connection — Azure Log Analytics Data Collector
// (used by the Logic App to write to the custom log table)
// ============================================================
resource laConnection 'Microsoft.Web/connections@2018-07-01-preview' = {
  name: laConnectionName
  location: location
  properties: {
    displayName: 'Falco → Log Analytics'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureloganalyticsdatacollector')
    }
    parameterValues: {
      username: workspace.properties.customerId
      password: workspace.listKeys().primarySharedKey
    }
  }
}

// ============================================================
// Logic App — HTTP trigger → Send Data to Log Analytics
// falcosidekick will POST Falco alerts here as JSON.
// ============================================================
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  properties: {
    state: 'Enabled'
    parameters: {
      '$connections': {
        value: {
          azureloganalyticsdatacollector: {
            connectionId: laConnection.id
            connectionName: laConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureloganalyticsdatacollector')
          }
        }
      }
    }
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
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                output: { type: 'string' }
                priority: { type: 'string' }
                rule: { type: 'string' }
                source: { type: 'string' }
                tags: { type: 'array' }
                time: { type: 'string' }
                output_fields: { type: 'object' }
                hostname: { type: 'string' }
              }
            }
          }
        }
      }
      actions: {
        Send_Data_to_Log_Analytics: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/api/logs'
            queries: {
              'Log-Type': 'FalcoAlerts'
            }
            body: '@triggerBody()'
          }
        }
        Response: {
          runAfter: {
            Send_Data_to_Log_Analytics: [ 'Succeeded' ]
          }
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
            body: {
              status: 'accepted'
            }
          }
        }
      }
    }
  }
}

// ============================================================
// AKS Cluster (managed identity, Container Insights enabled)
// ============================================================
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-05-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: clusterName
    nodeResourceGroup: nodeResourceGroup
    enableRBAC: true
    agentPoolProfiles: [
      {
        name: 'system'
        count: nodeCount
        vmSize: nodeVmSize
        mode: 'System'
        osType: 'Linux'
        osSKU: 'Ubuntu'
        type: 'VirtualMachineScaleSets'
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
    }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: workspace.id
        }
      }
    }
  }
}

// ============================================================
// Sentinel Scheduled Analytics Rule — Falco Alerts
// Creates an incident for Critical / Error / Warning alerts.
// ============================================================
resource falcoAnalyticRule 'Microsoft.SecurityInsights/alertRules@2023-12-01-preview' = {
  scope: workspace
  name: guid(workspace.id, 'FalcoRuntimeAlerts')
  kind: 'Scheduled'
  properties: {
    displayName: 'Falco — Runtime Security Alert (AKS)'
    description: 'Creates an incident when Falco reports a Critical, Error, or Warning rule violation from an AKS cluster.'
    severity: 'Medium'
    enabled: true
    query: '''${customLogTableName}
| where priority_s in ("Critical","Error","Warning","Emergency","Alert")
| extend RuleName = tostring(rule_s), Output = tostring(output_s), Priority = tostring(priority_s), Source = tostring(source_s), Hostname = tostring(hostname_s)
| project TimeGenerated, Priority, RuleName, Source, Hostname, Output, output_fields_s, tags_s'''
    queryFrequency: 'PT5M'
    queryPeriod: 'PT15M'
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionDuration: 'PT1H'
    suppressionEnabled: false
    tactics: [
      'Execution'
      'PrivilegeEscalation'
      'DefenseEvasion'
      'Persistence'
    ]
    incidentConfiguration: {
      createIncident: true
      groupingConfiguration: {
        enabled: true
        reopenClosedIncident: false
        lookbackDuration: 'PT1H'
        matchingMethod: 'AllEntities'
      }
    }
    eventGroupingSettings: {
      aggregationKind: 'SingleAlert'
    }
  }
  dependsOn: [
    sentinel
  ]
}

// ============================================================
// Outputs
// ============================================================
output workspaceId string = workspace.properties.customerId
output workspaceResourceId string = workspace.id
output workspaceName string = workspace.name
output aksClusterName string = aksCluster.name
output aksResourceGroup string = resourceGroup().name
output logicAppName string = logicApp.name
output customLogTable string = customLogTableName
