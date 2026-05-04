using './main-subscription.bicep'

// Resource Group Configuration
param resourceGroupName = 'rg-falco-demo-1'
param location = 'eastus'

// AKS Configuration
param aksClusterName = 'aks-falco-demo-1'
param kubernetesVersion = '1.33'
param nodeVmSize = 'Standard_D2s_v3'
param nodeCount = 3

// Log Analytics Configuration
param logAnalyticsWorkspaceName = 'law-falco-demo-1'
param enableSentinel = true

// Tags
param tags = {
  Environment: 'Demo'
  Purpose: 'Falco-Security-Audit'
  ManagedBy: 'Bicep'
}

// AKS Admin Principal ID - will be set by deployment script
param aksAdminPrincipalId = ''
