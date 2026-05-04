using './main.bicep'

param location = 'northeurope'
param projectName = 'falcosec'
param clusterName = 'falcosec-aks'
param kubernetesVersion = '1.34'
param nodeCount = 2
param nodeVmSize = 'Standard_D2s_v3'
param retentionInDays = 30
