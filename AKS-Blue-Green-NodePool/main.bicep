// ============================================================
// AKS with Blue-Green Node Pool Deployment Strategy
// ============================================================
// Deploys an AKS cluster with:
//   - A system node pool
//   - An initial "blue" user node pool for workloads
//   - System-assigned managed identity
//   - Azure CNI with overlay mode
// ============================================================
// After deployment, use blue-green-upgrade.sh to demonstrate
// creating a "green" node pool, migrating workloads, and
// removing the old "blue" node pool.
// ============================================================

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Name of the AKS cluster.')
param clusterName string = 'aks-bluegreen-cluster'

@description('DNS prefix for the AKS cluster.')
param dnsPrefix string = clusterName

@description('Kubernetes version for the cluster and node pools.')
@minLength(1)
param kubernetesVersion string = '1.30'

@description('VM size for the system node pool.')
param systemNodeVmSize string = 'Standard_DS2_v2'

@description('Number of nodes in the system node pool.')
@minValue(1)
@maxValue(10)
param systemNodeCount int = 2

@description('VM size for the blue (user) node pool.')
param blueNodeVmSize string = 'Standard_DS2_v2'

@description('Number of nodes in the blue (user) node pool.')
@minValue(1)
@maxValue(50)
param blueNodeCount int = 3

@description('Enable auto-scaling on the blue node pool.')
param enableAutoScaling bool = true

@description('Minimum node count when auto-scaling is enabled.')
@minValue(1)
param minNodeCount int = 1

@description('Maximum node count when auto-scaling is enabled.')
@maxValue(100)
param maxNodeCount int = 5

@description('SSH public key for node access. Leave empty to auto-generate.')
param sshPublicKey string = ''

@description('Admin username for AKS nodes.')
param adminUsername string = 'azureuser'

// ============================================================
// AKS Cluster with System + Blue Node Pools
// ============================================================
resource aksCluster 'Microsoft.ContainerService/managedClusters@2025-01-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: dnsPrefix
    kubernetesVersion: kubernetesVersion
    enableRBAC: true
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: systemNodeCount
        vmSize: systemNodeVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        mode: 'System'
        enableAutoScaling: false
        nodeLabels: {
          role: 'system'
        }
      }
      {
        name: 'blue'
        count: blueNodeCount
        vmSize: blueNodeVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        mode: 'User'
        enableAutoScaling: enableAutoScaling
        minCount: enableAutoScaling ? minNodeCount : null
        maxCount: enableAutoScaling ? maxNodeCount : null
        nodeLabels: {
          environment: 'blue'
        }
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
    }
    autoUpgradeProfile: {
      upgradeChannel: 'stable'
    }
    linuxProfile: sshPublicKey != '' ? {
      adminUsername: adminUsername
      ssh: {
        publicKeys: [
          {
            keyData: sshPublicKey
          }
        ]
      }
    } : null
  }
}

// ============================================================
// Outputs
// ============================================================

@description('The name of the AKS cluster.')
output clusterName string = aksCluster.name

@description('The resource ID of the AKS cluster.')
output clusterResourceId string = aksCluster.id

@description('The FQDN of the AKS cluster API server.')
output clusterFqdn string = aksCluster.properties.fqdn

@description('The Kubernetes version of the cluster.')
output kubernetesVersion string = aksCluster.properties.kubernetesVersion

@description('Command to get cluster credentials.')
output getCredentialsCommand string = 'az aks get-credentials --resource-group ${resourceGroup().name} --name ${aksCluster.name}'
