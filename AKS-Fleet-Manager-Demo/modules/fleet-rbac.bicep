// Fleet Manager RBAC Role Assignment

@description('Fleet Manager resource name')
param fleetName string

@description('Principal ID (User, Group, or Service Principal Object ID) to assign the role to')
param principalId string

@description('Principal type (User, Group, or ServicePrincipal)')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param principalType string = 'User'

// Azure Kubernetes Fleet Manager RBAC Cluster Admin role ID
var fleetClusterAdminRoleId = '18ab4d3d-a1bf-4477-8ad9-8359bc988f69'

resource fleet 'Microsoft.ContainerService/fleets@2024-05-02-preview' existing = {
  name: fleetName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(fleet.id, principalId, fleetClusterAdminRoleId)
  scope: fleet
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', fleetClusterAdminRoleId)
    principalId: principalId
    principalType: principalType
  }
}

output roleAssignmentId string = roleAssignment.id
output roleAssignmentName string = roleAssignment.name
