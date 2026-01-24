using './main.bicep'

param location = 'northeurope'
param memberCluster1Location = 'westeurope'
param memberCluster2Location = 'northeurope'
param cluster1KubernetesVersion = '1.33.5'
param cluster2KubernetesVersion = '1.33.5'
param cluster3KubernetesVersion = '1.32'
param cluster4KubernetesVersion = '1.32'
param cluster5KubernetesVersion = '1.32'
param environmentName = 'demo'
param resourceGroupName = 'rg-aks-fleet-demo-01'
param enableHubCluster = true
param tags = {
  Environment: 'Demo'
  Project: 'AKS-Fleet-Manager'
  ManagedBy: 'Bicep'
  CreatedDate: '2025-12-14'
}
