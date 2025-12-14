using './main.bicep'

param location = 'eastus'
param memberCluster1Location = 'eastus'
param memberCluster2Location = 'westus'
param environmentName = 'demo'
param resourceGroupName = 'rg-aks-fleet-demo'
param enableHubCluster = true
param tags = {
  Environment: 'Demo'
  Project: 'AKS-Fleet-Manager'
  ManagedBy: 'Bicep'
  CreatedDate: '2025-12-14'
}
