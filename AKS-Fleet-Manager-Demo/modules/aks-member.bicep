// AKS Member Cluster

@description('Name of the AKS cluster')
param clusterName string

@description('Location for the AKS cluster')
param location string

@description('Kubernetes version')
param kubernetesVersion string = '1.33'

@description('Subnet ID for the AKS cluster')
param subnetId string

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

@description('Resource tags')
param tags object = {}

@description('System node pool VM size')
param systemNodePoolVmSize string = 'Standard_DS2_v2'

@description('System node pool node count')
param systemNodePoolNodeCount int = 2

@description('Enable Azure Monitor for the cluster')
param enableAzureMonitor bool = true

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: clusterName
    kubernetesVersion: kubernetesVersion
    enableRBAC: true
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      serviceCidr: '172.16.0.0/22'
      dnsServiceIP: '172.16.0.10'
      loadBalancerSku: 'standard'
    }
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: systemNodePoolNodeCount
        vmSize: systemNodePoolVmSize
        mode: 'System'
        osType: 'Linux'
        vnetSubnetID: subnetId
        enableAutoScaling: true
        minCount: 1
        maxCount: 3
        maxPods: 110
      }
    ]
    addonProfiles: enableAzureMonitor ? {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
    } : {}
    autoUpgradeProfile: {
      upgradeChannel: 'stable'
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
  }
}

output clusterName string = aksCluster.name
output clusterResourceId string = aksCluster.id
output clusterFqdn string = aksCluster.properties.fqdn
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
