// Parameters file for BYO CNI AKS with Cilium Demo
using './main.bicep'

// Resource naming
param namePrefix = 'byocni'
param environment = 'dev'

// Location
param location = 'eastus'

// AKS Configuration
param kubernetesVersion = '1.34'
param systemNodeCount = 2
param systemNodeVmSize = 'Standard_D2s_v3'
param userNodeCount = 2
param userNodeVmSize = 'Standard_D4s_v3'

// Monitoring
param enableMonitoring = true

// Tags
param tags = {
  Environment: 'dev'
  Project: 'BYO-CNI-AKS-Cilium'
  ManagedBy: 'Bicep'
  Owner: 'DevOps'
}
