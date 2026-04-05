// ============================================================
// AKS with Advanced Container Networking Services (ACNS)
// ============================================================
// Deploys an AKS cluster with:
//   - Azure CNI with overlay mode
//   - Cilium data plane
//   - Advanced Container Networking Services enabled
//   - L7 advanced network policies (includes FQDN filtering)
// ============================================================

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Name of the AKS cluster.')
param clusterName string = 'aks-acns-cluster'

@description('DNS prefix for the AKS cluster.')
param dnsPrefix string = clusterName

@description('Kubernetes version. Must be 1.29 or later for ACNS.')
@minLength(1)
param kubernetesVersion string = '1.30'

@description('Number of nodes in the system node pool.')
@minValue(1)
@maxValue(50)
param nodeCount int = 2

@description('VM size for the system node pool.')
param nodeVmSize string = 'Standard_DS2_v2'

@description('SSH public key for node access. Leave empty to auto-generate.')
param sshPublicKey string = ''

@description('Admin username for AKS nodes.')
param adminUsername string = 'azureuser'

@description('Enable auto-scaling on the system node pool.')
param enableAutoScaling bool = true

@description('Minimum node count when auto-scaling is enabled.')
@minValue(1)
param minNodeCount int = 1

@description('Maximum node count when auto-scaling is enabled.')
@maxValue(100)
param maxNodeCount int = 5

@description('Advanced network policy level. Use "L7" for L7 + FQDN, or "FQDN" for FQDN-only filtering.')
@allowed([
  'L7'
  'FQDN'
])
param acnsAdvancedNetworkPolicies string = 'L7'

// ============================================================
// AKS Cluster with ACNS
// ============================================================
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
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
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        mode: 'System'
        enableAutoScaling: enableAutoScaling
        minCount: enableAutoScaling ? minNodeCount : null
        maxCount: enableAutoScaling ? maxNodeCount : null
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      advancedNetworking: {
        enabled: true
        observability: {
          enabled: true
        }
        security: {
          enabled: true
          fqdnPolicy: {
            enabled: true
          }
        }
      }
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

@description('The network data plane configured for the cluster.')
output networkDataplane string = aksCluster.properties.networkProfile.networkDataplane

@description('Command to get cluster credentials.')
output getCredentialsCommand string = 'az aks get-credentials --resource-group ${resourceGroup().name} --name ${aksCluster.name}'
