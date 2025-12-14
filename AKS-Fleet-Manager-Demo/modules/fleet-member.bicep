// AKS Fleet Member Resource

@description('Name of the Fleet Manager')
param fleetName string

@description('Name of the member cluster')
param memberClusterName string

@description('Resource ID of the member AKS cluster')
param memberClusterResourceId string

@description('Name for the fleet membership')
param memberName string

@description('Group name for the member cluster')
param group string = 'default'

resource fleet 'Microsoft.ContainerService/fleets@2024-05-02-preview' existing = {
  name: fleetName
}

resource fleetMember 'Microsoft.ContainerService/fleets/members@2024-05-02-preview' = {
  parent: fleet
  name: memberName
  properties: {
    clusterResourceId: memberClusterResourceId
    group: group
  }
}

output memberName string = fleetMember.name
output memberResourceId string = fleetMember.id
