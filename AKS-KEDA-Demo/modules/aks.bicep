// ============================================================
// Module: AKS Cluster with KEDA Add-on
//
// Creates an AKS cluster with:
//   - KEDA workload auto-scaler add-on
//   - OIDC issuer + Workload Identity
//   - Container Insights (Log Analytics)
//   - Azure Monitor metrics profile (Managed Prometheus)
// ============================================================

@description('Name of the AKS cluster.')
param clusterName string

@description('Azure region.')
param location string

@description('Kubernetes version.')
param kubernetesVersion string = '1.31'

@description('Number of system nodes.')
param nodeCount int = 2

@description('Node VM size.')
param nodeVmSize string = 'Standard_DS2_v2'

@description('Custom node resource group name.')
param nodeResourceGroupName string

@description('Log Analytics workspace resource ID for Container Insights.')
param logAnalyticsWorkspaceId string

@description('Resource tags.')
param tags object = {}

@description('Entra ID Object ID of the operator for AKS RBAC Cluster Admin. Leave empty to skip.')
param userId string = ''

// ============================================================
// AKS Cluster
// ============================================================

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: clusterName
    kubernetesVersion: kubernetesVersion
    nodeResourceGroup: nodeResourceGroupName
    enableRBAC: true
    networkProfile: {
      networkPlugin: 'azure'
      loadBalancerSku: 'standard'
    }
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: nodeCount
        vmSize: nodeVmSize
        mode: 'System'
        osType: 'Linux'
        maxPods: 110
      }
    ]
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
          useAADAuth: 'true'
        }
      }
    }
    azureMonitorProfile: {
      metrics: {
        enabled: true
        kubeStateMetrics: {
          metricLabelsAllowlist: ''
          metricAnnotationsAllowList: ''
        }
      }
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    workloadAutoScalerProfile: {
      keda: {
        enabled: true
      }
    }
  }
}

// ============================================================
// AKS RBAC Cluster Admin role assignment (optional)
// ============================================================

resource aksRbacClusterAdminRoleDef 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b'
  scope: subscription()
}

resource aksRbacClusterAdminAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(userId)) {
  name: guid(clusterName, userId, aksRbacClusterAdminRoleDef.id)
  scope: aksCluster
  properties: {
    roleDefinitionId: aksRbacClusterAdminRoleDef.id
    principalId: userId
    principalType: 'User'
  }
}

// ============================================================
// Outputs
// ============================================================

output aksClusterName string = aksCluster.name
output aksClusterId string = aksCluster.id
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
