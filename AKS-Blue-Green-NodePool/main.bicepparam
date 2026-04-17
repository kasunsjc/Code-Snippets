using 'main.bicep'

param location = 'northeurope'
param clusterName = 'aks-bluegreen-cluster'
param kubernetesVersion = '1.34'
param systemNodeCount = 2
param systemNodeVmSize = 'Standard_D2s_v4'
param userNodeVmSize = 'Standard_D2s_v4'
param userNodeCount = 3
param adminUsername = 'azureuser'
param enableAutoScaling = true
param minNodeCount = 1
param maxNodeCount = 10
