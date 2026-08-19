@description('Location for the resources.')
param location string = resourceGroup().location

@description('AKS cluster name.')
param clusterName string = 'aks-desktop-ai-demo'

@description('DNS prefix for the AKS cluster.')
param dnsPrefix string = clusterName

@description('Kubernetes version.')
param kubernetesVersion string = '1.35'

@description('Node count for the default system pool.')
param nodeCount int = 2

@description('VM size for the default system pool.')
param nodeVmSize string = 'Standard_D2s_v5'

resource aksCluster 'Microsoft.ContainerService/managedClusters@2026-05-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: dnsPrefix
    nodeResourceGroup: 'rg-${clusterName}-nodes'
    agentPoolProfiles: [
      {
        name: 'nodepool1'
        mode: 'System'
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
        osSKU: 'Ubuntu'
        type: 'VirtualMachineScaleSets'
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      loadBalancerSku: 'standard'
    }
  }
}

output aksClusterName string = aksCluster.name
output aksClusterResourceId string = aksCluster.id
