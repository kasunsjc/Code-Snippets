// AKS Cluster Module - Application Gateway for Containers
// Deploys AKS with Azure CNI Overlay, OIDC Issuer, and Workload Identity

@description('The name of the AKS cluster')
param clusterName string

@description('The location of the AKS cluster')
param location string

@description('Kubernetes version')
param kubernetesVersion string

@description('Number of nodes in the system node pool')
param systemNodeCount int

@description('VM size for system nodes')
param systemNodeVmSize string

@description('Subnet ID for AKS nodes')
param subnetId string

@description('Log Analytics Workspace ID for monitoring')
param logAnalyticsWorkspaceId string

@description('Enable monitoring')
param enableMonitoring bool

@description('Custom node resource group name')
param nodeResourceGroupName string

@description('Tags for the cluster')
param tags object

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
    enableRBAC: true

    agentPoolProfiles: [
      {
        name: 'system'
        count: systemNodeCount
        vmSize: systemNodeVmSize
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        vnetSubnetID: subnetId
        maxPods: 250
        enableAutoScaling: true
        minCount: 1
        maxCount: max(systemNodeCount, 3)
      }
    ]

    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'cilium'
      networkDataplane: 'cilium'
      podCidr: '10.244.0.0/16'
      serviceCidr: '10.2.0.0/16'
      dnsServiceIP: '10.2.0.10'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
    }

    oidcIssuerProfile: {
      enabled: true
    }

    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }

    addonProfiles: {
      omsagent: {
        enabled: enableMonitoring
        config: enableMonitoring ? {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        } : null
      }
    }
  }
}

output clusterName string = aksCluster.name
output clusterFqdn string = aksCluster.properties.fqdn
output nodeResourceGroup string = aksCluster.properties.nodeResourceGroup
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
