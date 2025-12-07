// Azure Container Registry Module

@description('Name of the Azure Container Registry')
param acrName string

@description('Location for the ACR')
param location string

@description('Tags for the ACR')
param tags object

@description('ACR SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Standard'

// Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
    zoneRedundancy: 'Disabled'
    dataEndpointEnabled: false
  }
}

// Outputs
output acrName string = acr.name
output loginServer string = acr.properties.loginServer
output acrId string = acr.id
