// AKS Cluster Module

@description('The name of the AKS cluster')
param clusterName string

@description('The location of the AKS cluster')
param location string

@description('Kubernetes version')
param kubernetesVersion string

@description('Number of nodes in the default node pool')
param nodeCount int

@description('VM size for the nodes')
param nodeVmSize string

@description('Subnet ID for AKS nodes')
param subnetId string

@description('Log Analytics Workspace ID for monitoring')
param logAnalyticsWorkspaceId string

@description('Enable monitoring')
param enableMonitoring bool

@description('Tags for the cluster')
param tags object

// AKS Cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
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
        name: 'agentpool'
        count: nodeCount
        vmSize: nodeVmSize
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        osType: 'Linux'
        osSKU: 'Ubuntu'
        vnetSubnetID: subnetId
        maxPods: 110
        enableAutoScaling: true
        minCount: 1
        maxCount: 5
        nodeTaints: []
        nodeLabels: {}
      }
    ]
    
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
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
      defender: {
        logAnalyticsWorkspaceResourceId: enableMonitoring ? logAnalyticsWorkspaceId : null
        securityMonitoring: {
          enabled: enableMonitoring
        }
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
