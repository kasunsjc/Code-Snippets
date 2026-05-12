using './main.bicep'

param location         = 'australiaeast'
param namePrefix       = 'vcluster'
param environment      = 'demo'
param kubernetesVersion = '1.31'
param systemNodeVmSize = 'Standard_D2s_v3'
param systemNodeCount  = 2
param userNodeVmSize   = 'Standard_D4s_v3'
param userNodeCount    = 3
param enableMonitoring = true
param tags = {
  Environment: 'Demo'
  Project: 'VCluster-Demo'
  ManagedBy: 'Bicep'
  CreatedDate: '2026-05-12'
  YouTube: 'true'
}
