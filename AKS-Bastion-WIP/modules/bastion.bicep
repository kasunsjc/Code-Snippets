targetScope = 'resourceGroup'

@description('Location for the Bastion')
param location string

@description('Name of the Bastion host')
param bastionName string

@description('Subnet ID for Azure Bastion')
param bastionSubnetId string

@description('Tags to apply to resources')
param tags object = {}

// Public IP for Bastion
resource bastionPublicIP 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: '${bastionName}-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// Azure Bastion Host
resource bastionHost 'Microsoft.Network/bastionHosts@2023-11-01' = {
  name: bastionName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    enableTunneling: true
    enableFileCopy: true
    enableIpConnect: true
    enableShareableLink: false
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: bastionSubnetId
          }
          publicIPAddress: {
            id: bastionPublicIP.id
          }
        }
      }
    ]
  }
}

// Outputs
output bastionId string = bastionHost.id
output bastionName string = bastionHost.name
output publicIPAddress string = bastionPublicIP.properties.ipAddress
