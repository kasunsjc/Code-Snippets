// modules/aks.bicep
// AKS cluster module for the vcluster host

@description('Name of the AKS cluster')
param clusterName string

@description('Azure region')
param location string = resourceGroup().location

@description('Kubernetes version')
param kubernetesVersion string = '1.31'

@description('System node pool VM size')
param systemNodeVmSize string = 'Standard_D2s_v3'

@description('System node pool count')
param systemNodeCount int = 2

@description('User node pool VM size')
param userNodeVmSize string = 'Standard_D4s_v3'

@description('User node pool count')
param userNodeCount int = 3

@description('System node pool minimum count when autoscaling is enabled')
@minValue(1)
param systemNodeMinCount int = 1

@description('System node pool maximum count when autoscaling is enabled')
@maxValue(5)
param systemNodeMaxCount int = 3

@description('User node pool minimum count when autoscaling is enabled')
@minValue(1)
param userNodeMinCount int = 2

@description('User node pool maximum count when autoscaling is enabled')
@maxValue(10)
param userNodeMaxCount int = 6

@description('VNet subnet resource ID for Azure CNI')
param vnetSubnetId string

@description('Log Analytics workspace resource ID (empty string to skip)')
param logAnalyticsWorkspaceId string = ''

@description('Enable Container Insights monitoring')
param enableMonitoring bool = true

@description('Custom node resource group name')
param nodeResourceGroup string

@description('Tags')
param tags object = {}

resource aks 'Microsoft.ContainerService/managedClusters@2024-01-01' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: clusterName
    nodeResourceGroup: nodeResourceGroup

    agentPoolProfiles: [
      // System node pool — runs kube-system / AKS add-ons
      {
        name: 'system'
        count: systemNodeCount
        vmSize: systemNodeVmSize
        osType: 'Linux'
        osSKU: 'Ubuntu'
        mode: 'System'
        vnetSubnetID: vnetSubnetId
        maxPods: 110
        enableAutoScaling: true
        minCount: systemNodeMinCount
        maxCount: systemNodeMaxCount
        type: 'VirtualMachineScaleSets'
      }
      // User node pool — hosts all vclusters and demo workloads
      {
        name: 'user'
        count: userNodeCount
        vmSize: userNodeVmSize
        osType: 'Linux'
        osSKU: 'Ubuntu'
        mode: 'User'
        vnetSubnetID: vnetSubnetId
        maxPods: 110
        enableAutoScaling: true
        minCount: userNodeMinCount
        maxCount: userNodeMaxCount
        type: 'VirtualMachineScaleSets'
      }
    ]

    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'azure'
      serviceCidr: '10.96.0.0/16'
      dnsServiceIP: '10.96.0.10'
      loadBalancerSku: 'standard'
    }

    addonProfiles: {
      omsagent: enableMonitoring && !empty(logAnalyticsWorkspaceId) ? {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      } : {
        enabled: false
      }
    }

    autoUpgradeProfile: {
      upgradeChannel: 'patch'
    }

    enableRBAC: true
  }
}

output clusterName string = aks.name
output clusterFqdn string = aks.properties.fqdn
output kubeletIdentityObjectId string = aks.properties.identityProfile.kubeletidentity.objectId
output clusterIdentityPrincipalId string = aks.identity.principalId
