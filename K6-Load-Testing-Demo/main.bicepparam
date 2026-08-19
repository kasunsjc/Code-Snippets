using './main.bicep'

param location = 'northeurope'
param clusterName = 'aks-k6-demo'
param userId = ''
param nodeVmSize = 'Standard_D4s_v6'
param tags = {
  Environment: 'Demo'
  Project: 'K6-Load-Testing'
  ManagedBy: 'Bicep'
  CreatedDate: '2026-08-02'
}
