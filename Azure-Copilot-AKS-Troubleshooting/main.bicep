// Main Bicep template for Azure Copilot AKS Troubleshooting Demo
// Deploys an AKS cluster with monitoring enabled

targetScope = 'resourceGroup'

@description('The Azure region for all resources')
param location string = resourceGroup().location

@description('AKS cluster name')
param aksClusterName string = 'copilot-aks-demo'

@description('AKS Kubernetes version')
param kubernetesVersion string = '1.34'

@description('AKS node count')
@minValue(1)
@maxValue(5)
param nodeCount int = 2

@description('AKS node VM size')
param nodeVmSize string = 'Standard_D2s_v3'

@description('Tags to apply to all resources')
param tags object = {
  Project: 'Azure-Copilot-AKS-Troubleshooting'
  Purpose: 'Demo'
  ManagedBy: 'Bicep'
}

// Log Analytics Workspace for Container Insights
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${aksClusterName}-logs'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// AKS Cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: aksClusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: aksClusterName
    kubernetesVersion: kubernetesVersion
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: nodeCount
        vmSize: nodeVmSize
        mode: 'System'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        enableAutoScaling: false
      }
    ]
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalytics.id
        }
      }
    }
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
    }
  }
}

output aksClusterName string = aksCluster.name
output aksClusterFqdn string = aksCluster.properties.fqdn
output logAnalyticsWorkspaceId string = logAnalytics.id
