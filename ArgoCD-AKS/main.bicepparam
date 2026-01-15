using './main.bicep'

param location = 'eastus'
param environmentName = 'dev'
param baseName = 'argocd'

param tags = {
  Environment: 'Development'
  Project: 'ArgoCD-AKS-Demo'
  ManagedBy: 'Bicep'
  Purpose: 'Demo'
}

param aksConfig = {
  kubernetesVersion: '1.34.0'
  nodeCount: 3
  nodeVmSize: 'Standard_D4s_v3'
  maxPods: 110
  enableMonitoring: true
  networkPlugin: 'azure'
  networkPolicy: 'azure'
}

param networkConfig = {
  vnetAddressPrefix: '10.0.0.0/16'
  aksSubnetAddressPrefix: '10.0.0.0/22'
}

param logAnalyticsConfig = {
  retentionInDays: 30
  sku: 'PerGB2018'
}
