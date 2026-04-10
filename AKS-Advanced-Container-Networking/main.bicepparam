using 'main.bicep'

param location = 'northeurope'
param clusterName = 'aks-acns-cluster'
param kubernetesVersion = '1.34'
param nodeCount = 2
param nodeVmSize = 'Standard_D2s_v4'
param adminUsername = 'azureuser'
param enableAutoScaling = true
param minNodeCount = 1
param maxNodeCount = 5
