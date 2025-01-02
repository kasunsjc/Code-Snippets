
@description('prefix for the resources')
param prefix string

@description('Location of the Azure region to deploy the resources')
param location string = 'northeurope'

@description('Public IP Range ID')
param publicIpRangeId string


resource natGateway 'Microsoft.Network/natGateways@2024-05-01' = {
  name: '${prefix}-nat-gateway'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpPrefixes: [
      {
        id: publicIpRangeId
      }
    ]
  }
}

output natGatewayId string = natGateway.id
