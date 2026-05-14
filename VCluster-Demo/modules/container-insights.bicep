// modules/container-insights.bicep
// Enables Container Insights v2 (ContainerLogV2) on an existing AKS cluster.
//
// Why a DCR + DCRA is required:
//   The omsagent addon installs Azure Monitor Agent but only writes to the
//   legacy ContainerLog (V1) table by default. ContainerLogV2 requires a
//   Data Collection Rule with enableContainerLogV2: true and a Data Collection
//   Rule Association named 'ContainerInsightsExtension' scoped to the cluster.

@description('Name of the existing AKS cluster to associate with')
param clusterName string

@description('Resource ID of the Log Analytics workspace to send logs to')
param logAnalyticsWorkspaceId string

@description('Azure region — must match the AKS cluster region')
param location string = resourceGroup().location

@description('Tags applied to the DCR')
param tags object = {}

// Reference to the existing AKS cluster — used as scope for the DCRA
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-01-01' existing = {
  name: clusterName
}

// ---------------------------------------------------------------------------
// Data Collection Rule — enables ContainerLogV2 schema
// ---------------------------------------------------------------------------
resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: '${clusterName}-ci-dcr'
  location: location
  tags: tags
  properties: {
    description: 'Container Insights DCR — ContainerLogV2 for ${clusterName}'
    dataSources: {
      extensions: [
        {
          name: 'ContainerInsightsExtension'
          extensionName: 'ContainerInsightsExtension'
          streams: [
            'Microsoft-ContainerLogV2'
            'Microsoft-KubeEvents'
            'Microsoft-KubePodInventory'
            'Microsoft-KubeNodeInventory'
            'Microsoft-KubeServices'
            'Microsoft-ContainerInventory'
            'Microsoft-ContainerNodeInventory'
            'Microsoft-Perf'
          ]
          extensionSettings: {
            dataCollectionSettings: {
              interval: '1m'
              enableContainerLogV2: true
              namespaceFilteringMode: 'Off'
              namespaces: []
            }
          }
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspaceId
          name: 'ciworkspace'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-ContainerLogV2'
          'Microsoft-KubeEvents'
          'Microsoft-KubePodInventory'
          'Microsoft-KubeNodeInventory'
          'Microsoft-KubeServices'
          'Microsoft-ContainerInventory'
          'Microsoft-ContainerNodeInventory'
          'Microsoft-Perf'
        ]
        destinations: [
          'ciworkspace'
        ]
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Data Collection Rule Association — links the DCR to the AKS cluster
// ---------------------------------------------------------------------------
// The name 'ContainerInsightsExtension' is a reserved value required by AKS
// Container Insights — do not change it.
resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'ContainerInsightsExtension'
  scope: aksCluster
  properties: {
    description: 'Association between ${clusterName} and the Container Insights DCR'
    dataCollectionRuleId: dcr.id
  }
}

output dcrId string = dcr.id
