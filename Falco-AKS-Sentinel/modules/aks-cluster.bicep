// ========================================
// AKS Cluster Module
// ========================================

@description('The name of the AKS cluster')
param clusterName string

@description('The location for the cluster')
param location string

@description('The Kubernetes version')
param kubernetesVersion string

@description('The VM size for nodes')
param nodeVmSize string

@description('The number of nodes')
@minValue(1)
@maxValue(10)
param nodeCount int

@description('Log Analytics workspace resource ID')
param logAnalyticsWorkspaceId string

@description('Resource tags')
param tags object = {}

@description('Enable Azure RBAC for Kubernetes authorization')
param enableAzureRbac bool = true

@description('Network plugin to use')
@allowed([
  'azure'
  'kubenet'
])
param networkPlugin string = 'azure'

@description('The Azure AD user or group object ID to grant AKS RBAC Cluster Admin role')
param aksAdminPrincipalId string

@description('Custom node resource group name (where AKS-managed VMSS, NICs, etc. live).')
param nodeResourceGroupName string = 'rg-${clusterName}-nodes'

// ========================================
// AKS Managed Cluster
// ========================================
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-02-preview' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: '${clusterName}-dns'
    enableRBAC: true
    nodeResourceGroup: nodeResourceGroupName
    
    // AAD Integration with Azure RBAC
    aadProfile: {
      managed: true
      enableAzureRBAC: enableAzureRbac
    }

    // Agent Pool Configuration
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        enableAutoScaling: false
        maxPods: 110
        osDiskSizeGB: 128
        osDiskType: 'Managed'
      }
    ]

    // Network Configuration
    networkProfile: {
      networkPlugin: networkPlugin
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
    }

    // Monitoring Configuration
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
      azurepolicy: {
        enabled: true
      }
    }

    // Security Configuration
    securityProfile: {
      defender: {
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceId
        securityMonitoring: {
          enabled: true
        }
      }
    }

    // Auto-upgrade Configuration
    autoUpgradeProfile: {
      upgradeChannel: 'stable'
    }

    // Auto-scaler Profile
    autoScalerProfile: {
      'scale-down-delay-after-add': '10m'
      'scale-down-unneeded-time': '10m'
    }
  }
}

// ========================================
// RBAC Role Assignment - AKS RBAC Cluster Admin
// ========================================
resource aksClusterAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aksCluster
  name: guid(aksCluster.id, aksAdminPrincipalId, 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b')
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b') // Azure Kubernetes Service RBAC Cluster Admin
    principalId: aksAdminPrincipalId
    principalType: 'User'
  }
}

// ========================================
// Diagnostic Settings for AKS
// ========================================
resource aksClusterDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: aksCluster
  name: 'aks-diagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'kube-apiserver'
        enabled: true
      }
      {
        category: 'kube-controller-manager'
        enabled: true
      }
      {
        category: 'kube-scheduler'
        enabled: true
      }
      {
        category: 'kube-audit'
        enabled: true
      }
      {
        category: 'kube-audit-admin'
        enabled: true
      }
      {
        category: 'guard'
        enabled: true
      }
      {
        category: 'cluster-autoscaler'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ========================================
// Outputs
// ========================================

@description('The resource ID of the AKS cluster')
output clusterResourceId string = aksCluster.id

@description('The name of the AKS cluster')
output clusterName string = aksCluster.name

@description('The FQDN of the AKS cluster')
output clusterFqdn string = aksCluster.properties.fqdn

@description('The kubelet identity object ID')
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
