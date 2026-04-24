// Application Gateway for Containers Module (BYO Deployment Strategy)
// Creates the AGFC resource, frontend, and association in Azure
// Lifecycle is managed in Azure, independent from Kubernetes

@description('Name of the Application Gateway for Containers resource')
param agfcName string

@description('Location for the AGFC resource')
param location string

@description('Name of the frontend resource')
param frontendName string = 'frontend'

@description('Name of the association resource')
param associationName string = 'association'

@description('Subnet ID for the ALB association (must be delegated to Microsoft.ServiceNetworking/trafficControllers)')
param albSubnetId string

@description('Tags for resources')
param tags object

resource agfc 'Microsoft.ServiceNetworking/trafficControllers@2025-01-01' = {
  name: agfcName
  location: location
  tags: tags
  properties: {}
}

resource frontend 'Microsoft.ServiceNetworking/trafficControllers/frontends@2025-01-01' = {
  parent: agfc
  name: frontendName
  location: location
  properties: {}
}

resource association 'Microsoft.ServiceNetworking/trafficControllers/associations@2025-01-01' = {
  parent: agfc
  name: associationName
  location: location
  properties: {
    associationType: 'subnets'
    subnet: {
      id: albSubnetId
    }
  }
}

output agfcId string = agfc.id
output agfcName string = agfc.name
output frontendName string = frontend.name
output frontendFqdn string = frontend.properties.fqdn
