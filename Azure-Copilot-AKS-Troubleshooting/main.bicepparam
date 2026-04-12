using 'main.bicep'

param location = 'eastus'
param aksClusterName = 'copilot-aks-demo'
param kubernetesVersion = '1.31.2'
param nodeCount = 2
param nodeVmSize = 'Standard_D2s_v3'
