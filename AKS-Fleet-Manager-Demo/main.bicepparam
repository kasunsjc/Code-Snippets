using './main.bicep'

param location = 'northeurope'
param clusterLocation1 = 'westeurope'
param clusterLocation2 = 'northeurope'
param devKubernetesVersion = '1.33'
param accKubernetesVersion = '1.33.5'
param prodKubernetesVersion = '1.33'
param environmentName = 'demo'
param resourceGroupName = 'rg-aks-fleet-demo'
param enableHubCluster = true
param tags = {
  Environment: 'Demo'
  Project: 'AKS-Fleet-Manager'
  ManagedBy: 'Bicep'
  CreatedDate: '2025-12-14'
}
