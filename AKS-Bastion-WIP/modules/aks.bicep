targetScope = 'resourceGroup'

@description('Location for the AKS cluster')
param location string

@description('Name of the AKS cluster')
param clusterName string

@description('DNS prefix for the AKS cluster')
param dnsPrefix string

@description('Kubernetes version')
param kubernetesVersion string = '1.33.0'

@description('Number of nodes in the default node pool')
param agentCount int = 2

@description('VM size for the nodes')
param agentVMSize string = 'Standard_D2s_v3'

@description('Subnet ID for AKS nodes')
param subnetId string

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

@description('Tags to apply to resources')
param tags object = {}

// Private AKS Cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: dnsPrefix
    kubernetesVersion: kubernetesVersion
    enableRBAC: true
    apiServerAccessProfile: {
      enablePrivateCluster: true
      enablePrivateClusterPublicFQDN: false
    }
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      serviceCidr: '172.16.0.0/16'
      dnsServiceIP: '172.16.0.10'
      loadBalancerSku: 'standard'
    }
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: agentCount
        vmSize: agentVMSize
        osType: 'Linux'
        mode: 'System'
        vnetSubnetID: subnetId
        type: 'VirtualMachineScaleSets'
        enableAutoScaling: false
      }
    ]
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
      azurePolicy: {
        enabled: true
      }
    }
  }
}

// Outputs
output clusterName string = aksCluster.name
output clusterId string = aksCluster.id
output controlPlaneFQDN string = aksCluster.properties.privateFQDN
output kubeletIdentity string = aksCluster.properties.identityProfile.kubeletidentity.objectId
