// K6 Load Testing Demo — Main Deployment (simplified: no Prometheus/Grafana)
// Provisions AKS cluster only; k6 results are read from pod logs.
targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Base name for all resources')
param clusterName string = 'aks-k6-demo'

@description('Object ID of the user to receive AKS Cluster Admin role')
param userId string = ''

@description('Tags applied to all resources')
param tags object = {
  Environment: 'Demo'
  Project: 'K6-Load-Testing'
  ManagedBy: 'Bicep'
}

// ========== AKS Cluster ==========

module aks 'modules/aks.bicep' = {
  name: 'aks-deployment'
  params: {
    clusterName: clusterName
    location: location
    userId: userId
    tags: tags
  }
}

// ========== Outputs ==========

output aksClusterName string = aks.outputs.aksClusterName
