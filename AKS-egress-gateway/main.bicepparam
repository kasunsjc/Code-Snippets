using './main.bicep'

param location = 'northeurope'
param prefix = 'aks'
param addressPrefix = ['10.30.0.0/16']
param aksSubnetPrefix = '10.30.1.0/24'
param kubeVersion = '1.30.0'
param networkProfile = 'azure'
param networkPluginMode = 'overlay'
param enableManagedNatGateway = false
param userDefineNATGateway = true


