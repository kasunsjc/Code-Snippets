// Role Assignment for AKS to pull from ACR

@description('Name of the Azure Container Registry')
param acrName string

@description('Principal ID of AKS kubelet identity')
param aksPrincipalId string

// Reference to existing ACR
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// AcrPull role definition ID
var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

// Role Assignment
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, aksPrincipalId, acrPullRoleDefinitionId)
  scope: acr
  properties: {
    roleDefinitionId: acrPullRoleDefinitionId
    principalId: aksPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output roleAssignmentId string = roleAssignment.id
