// Azure OpenAI Module

@description('Name of the Azure OpenAI resource')
param openAiName string

@description('Location for the Azure OpenAI resource')
param location string

@description('Model name to deploy')
param modelName string

@description('Model version')
param modelVersion string

@description('Model capacity (TPM in thousands)')
param modelCapacity int

@description('Tags for the resource')
param tags object

// Azure OpenAI Account
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: openAiName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: openAiName
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Model Deployment
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: openAiAccount
  name: modelName
  sku: {
    name: 'Standard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    raiPolicyName: 'Microsoft.Default'
  }
}

// Outputs
output name string = openAiAccount.name
output endpoint string = openAiAccount.properties.endpoint
output resourceId string = openAiAccount.id
output modelDeploymentName string = modelDeployment.name
output apiVersion string = '2024-08-01-preview'
