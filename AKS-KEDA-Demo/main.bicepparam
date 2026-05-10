using 'main.bicep'

param location       = 'australiaeast'
param clusterName    = 'aks-keda-demo'
param kubernetesVersion = '1.31'
param nodeCount      = 2
param nodeVmSize     = 'Standard_DS2_v2'
param tags           = {
  Environment: 'Demo'
  Project: 'AKS-KEDA'
  ManagedBy: 'Bicep'
}
