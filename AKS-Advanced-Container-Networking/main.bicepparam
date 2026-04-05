using 'main.bicep'

param location = 'eastus'
param clusterName = 'aks-acns-cluster'
param kubernetesVersion = '1.30'
param nodeCount = 2
param nodeVmSize = 'Standard_DS2_v2'
param adminUsername = 'azureuser'
param enableAutoScaling = true
param minNodeCount = 1
param maxNodeCount = 5
param acnsAdvancedNetworkPolicies = 'L7'
