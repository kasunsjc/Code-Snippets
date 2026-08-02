using './main.bicep'

param location = 'northeurope'
param clusterName = 'aks-k6-demo'
param userId = ''
param tags = {
  Environment: 'Demo'
  Project: 'K6-Load-Testing'
  ManagedBy: 'Bicep'
  CreatedDate: '2026-08-02'
}
