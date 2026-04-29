using './main.bicep'

param location = 'northeurope'
param projectName = 'falcosec'
param clusterName = 'falcosec-aks'
param kubernetesVersion = '1.30'
param nodeCount = 2
param nodeVmSize = 'Standard_DS2_v2'
param retentionInDays = 30
