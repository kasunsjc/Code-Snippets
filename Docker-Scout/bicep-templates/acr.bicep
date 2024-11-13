@description('Container Registry Name')
param acrName string

@description('Location for all resources.')
param location string 

@description('Deploy Azure Container Registry')
resource acr 'Microsoft.ContainerRegistry/registries@2021-06-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: false
  }
}
