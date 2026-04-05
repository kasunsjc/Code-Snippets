// AKS Cluster Module - BYO CNI Configuration
// Deploys AKS with networkPlugin 'none' for Cilium CNI installation

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

@description('Number of nodes in the user node pool')
param userNodeCount int

@description('VM size for user nodes')
param userNodeVmSize string

@description('Subnet ID for AKS nodes')
param subnetId string

@description('Log Analytics Workspace ID for monitoring')
param logAnalyticsWorkspaceId string

@description('Enable monitoring')
param enableMonitoring bool

@description('Tags for the cluster')
param tags object

// AKS Cluster with BYO CNI (networkPlugin: none)
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
        maxPods: 110
        enableAutoScaling: true
        minCount: 1
        maxCount: 3
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
        nodeLabels: {
          'nodepool-type': 'system'
        }
      }
      {
        name: 'userpool'
        count: userNodeCount
        vmSize: userNodeVmSize
        mode: 'User'
        type: 'VirtualMachineScaleSets'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        vnetSubnetID: subnetId
        maxPods: 110
        enableAutoScaling: true
        minCount: 1
        maxCount: 5
        nodeLabels: {
          'nodepool-type': 'user'
        }
      }
    ]

    // BYO CNI - networkPlugin set to 'none'
    // Cilium will be installed post-deployment via Helm
    networkProfile: {
      networkPlugin: 'none'
      networkPolicy: 'none'
      podCidr: '10.244.0.0/16'
      serviceCidr: '10.2.0.0/16'
      dnsServiceIP: '10.2.0.10'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
    }

    addonProfiles: enableMonitoring && !empty(logAnalyticsWorkspaceId) ? {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
      azurepolicy: {
        enabled: true
      }
    } : {
      azurepolicy: {
        enabled: true
      }
    }

    apiServerAccessProfile: {
      enablePrivateCluster: false
    }

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

// Outputs
output clusterName string = aksCluster.name
output clusterFqdn string = aksCluster.properties.fqdn
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
output aksResourceId string = aksCluster.id
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL
