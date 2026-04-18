// Parameters file for AKS with Application Gateway for Containers Demo
using './main.bicep'

param namePrefix = 'agfc'
param environment = 'dev'
param location = 'northeurope'
param kubernetesVersion = '1.34.2'
param systemNodeCount = 2
param systemNodeVmSize = 'Standard_D2s_v3'
param enableMonitoring = true

// Deployment strategy: 'byo' or 'managed'
// - 'byo'     : AGFC resource created in Azure via Bicep, referenced by Gateway in K8s
// - 'managed' : AGFC resource created automatically via ApplicationLoadBalancer CRD in K8s
param deploymentStrategy = 'managed'

param tags = {
  Environment: 'dev'
  Project: 'AKS-AppGW-Containers'
  ManagedBy: 'Bicep'
  Owner: 'DevOps'
}
