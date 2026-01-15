using './main.bicep'

param location = 'eastus'
param aksClusterName = 'aks-private-demo'
param dnsPrefix = 'aksprivatedemo'
param kubernetesVersion = '1.33.0'
param agentVMSize = 'Standard_D2s_v3'
param agentCount = 2
param vnetName = 'vnet-aks-bastion-demo'
param bastionName = 'bastion-aks-demo'
param tags = {
  Environment: 'Demo'
  Purpose: 'AKS-Bastion-Demo'
  CreatedBy: 'Bicep'
}
