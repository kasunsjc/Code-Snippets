// ============================================================
// AKS KEDA Demo - Infrastructure Deployment
// Deploys an AKS cluster with the KEDA add-on enabled plus
// supporting resources for the demo scenarios.
//
// Scenarios covered:
//   01 - Azure Storage Queue scaler
//   02 - Azure Service Bus Queue scaler
//   03 - Cron (time-based) scaler
//   04 - Prometheus scaler
//   05 - CPU / Memory scaler
// ============================================================

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Name of the AKS cluster.')
param clusterName string = 'aks-keda-demo'

@description('Kubernetes version.')
param kubernetesVersion string = '1.31'

@description('Number of nodes in the default system node pool.')
param nodeCount int = 2

@description('VM size for agent nodes.')
param nodeVmSize string = 'Standard_DS2_v2'

@description('Tags applied to all resources.')
param tags object = {
  Environment: 'Demo'
  Project: 'AKS-KEDA'
  ManagedBy: 'Bicep'
}

// ============================================================
// Variables
// ============================================================

var storageAccountName = take(replace(toLower('st${clusterName}keda'), '-', ''), 24)
var serviceBusNamespaceName = '${clusterName}-sb'
var nodeResourceGroupName = 'rg-${clusterName}-nodes'

// ============================================================
// Log Analytics Workspace
// ============================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${clusterName}-law'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// ============================================================
// AKS Cluster with KEDA Add-on
// ============================================================

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: clusterName
    nodeResourceGroup: nodeResourceGroupName

    agentPoolProfiles: [
      {
        name: 'system'
        count: nodeCount
        vmSize: nodeVmSize
        mode: 'System'
        osType: 'Linux'
        osDiskSizeGB: 50
        enableAutoScaling: false
      }
    ]

    // ----- KEDA Add-on (Workload Autoscaler) -----
    workloadAutoScalerProfile: {
      keda: {
        enabled: true
      }
    }

    // ----- Workload Identity + OIDC Issuer -----
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }

    // ----- Monitoring -----
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspace.id
        }
      }
    }

    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      loadBalancerSku: 'standard'
    }
  }
}

// ============================================================
// Azure Storage Account + Queue  (Scenario 01)
// ============================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource storageQueueService 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource storageQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = {
  parent: storageQueueService
  name: 'keda-demo-queue'
}

// ============================================================
// Azure Service Bus Namespace + Queue  (Scenario 02)
// ============================================================

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
}

resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'keda-demo-queue'
  properties: {
    maxDeliveryCount: 10
    lockDuration: 'PT1M'
    defaultMessageTimeToLive: 'P1D'
  }
}

// ============================================================
// Outputs
// ============================================================

output aksClusterName string = aksCluster.name
output nodeResourceGroup string = nodeResourceGroupName
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL
output storageAccountName string = storageAccount.name
output storageQueueName string = storageQueue.name
output serviceBusNamespaceName string = serviceBusNamespace.name
output serviceBusQueueName string = serviceBusQueue.name
