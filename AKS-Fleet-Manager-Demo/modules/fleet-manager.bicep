// AKS Fleet Manager Resource

@description('Name of the Fleet Manager')
param fleetName string

@description('Location for the Fleet Manager')
param location string

@description('Enable hub cluster for the fleet')
param enableHubCluster bool = true

@description('Resource tags')
param tags object = {}

resource fleetManager 'Microsoft.ContainerService/fleets@2024-05-02-preview' = {
  name: fleetName
  location: location
  tags: tags
  properties: {
    hubProfile: enableHubCluster ? {
      dnsPrefix: '${fleetName}-hub'
    } : null
  }
}

output fleetName string = fleetManager.name
output fleetResourceId string = fleetManager.id
output fleetLocation string = fleetManager.location
