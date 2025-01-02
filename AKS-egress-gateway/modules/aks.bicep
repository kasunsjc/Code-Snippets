@description('prefix for the resources')
param prefix string

@description('Location of the Azure region to deploy the resources')
param location string = 'northeurope'

@description('Kubernetes Version')
param kubeVersion string = '1.30.0'

@description('Network Profile e.g. azure, kubenet')
param networkProfile string = 'azure'

@description('Virtual Network ID')
param aksSubnetId string

@description('Network Plugin Mode e.g. overlay')
param networkPluginMode string = 'overlay'

@description('Virtual Machine Size')
param vmSize string = 'Standard_D2_v2'

@description('Condition to check if the NAT Gateway is enabled')
param enableManagedNatGateway bool = false

@description('Condition to check if the user defined NAT Gateway is enabled')
param userDefineNATGateway bool = false

var outboundType = enableManagedNatGateway == true ? 'managedNATGateway' : userDefineNATGateway == true ?'userDefineNATGateway' : 'loadBalancer'

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-02-preview' = {
  name: '${prefix}-egress-01'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: '${prefix}-egress-01'
    kubernetesVersion: kubeVersion
    nodeResourceGroup: '${prefix}-node-rg'
    enableRBAC: true
    networkProfile: {
      networkPlugin: networkProfile
      networkPluginMode: networkProfile == 'kubenet' ? 'null' : networkPluginMode
      outboundType: outboundType
    }
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: 1
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        vmSize: vmSize
        osType: 'Linux'
        osDiskSizeGB: 30
        vnetSubnetID: enableManagedNatGateway == false ? aksSubnetId : 'null'
      }
      {
        name: 'app'
        count: 1
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        vmSize: vmSize
        osType: 'Linux'
        osDiskSizeGB: 30
        vnetSubnetID: enableManagedNatGateway == false ? aksSubnetId : 'null'
      }
    ]
  }
}
