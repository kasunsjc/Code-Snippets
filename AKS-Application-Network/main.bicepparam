using './main.bicep'

param location = 'eastus'
param environmentName = 'demo'
param aksResourceGroupName = 'rg-appnet-demo'
param appNetResourceGroupName = 'rg-appnet-resource-demo'
param clusterName = 'aks-appnet-demo'
param kubernetesVersion = '1.32'
param systemNodeVmSize = 'Standard_D2s_v3'
param systemNodeCount = 2
param tags = {
  Environment: 'Demo'
  Project: 'AKS-Application-Network'
  ManagedBy: 'Bicep'
  CreatedDate: '2026-06-02'
}
