// AKS Cluster Module for Application Network Demo
// Creates an AKS cluster with the required configuration for Application Network membership:
//   - AKS-managed Microsoft Entra integration
//   - OIDC issuer
//   - Managed Kubernetes Gateway API
//   - NO Istio service mesh add-on

@description('AKS cluster name')
param clusterName string

@description('Azure region')
param location string

@description('Kubernetes version')
param kubernetesVersion string = '1.32'

@description('Custom node resource group name')
param nodeResourceGroupName string

@description('System node pool VM size')
param systemNodeVmSize string = 'Standard_D2s_v3'

@description('System node pool node count')
param systemNodeCount int = 2

@description('Log Analytics workspace resource ID for monitoring')
param logAnalyticsWorkspaceId string

@description('Tags')
param tags object = {}

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

    // AKS-managed Microsoft Entra integration (required for Application Network)
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }

    // OIDC issuer (required for Application Network)
    oidcIssuerProfile: {
      enabled: true
    }

    // Network configuration - using Azure CNI
    // NOTE: Istio service mesh add-on must NOT be enabled
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      loadBalancerSku: 'standard'
    }

    // System node pool
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: systemNodeCount
        vmSize: systemNodeVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        mode: 'System'
        enableAutoScaling: true
        minCount: 2
        maxCount: 5
        type: 'VirtualMachineScaleSets'
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
      }
    ]

    // Azure Monitor integration
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
          useAADAuth: 'true'
        }
      }
    }

    // Security profile
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }

    autoUpgradeProfile: {
      upgradeChannel: 'patch'
      nodeOSUpgradeChannel: 'NodeImage'
    }
  }
}

output clusterName string = aksCluster.name
output clusterResourceId string = aksCluster.id
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
output clusterPrincipalId string = aksCluster.identity.principalId
