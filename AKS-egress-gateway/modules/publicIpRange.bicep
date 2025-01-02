
@description('prefix for the resources')
param prefix string

@description('Location of the Azure region to deploy the resources')
param location string = 'northeurope'


resource publicIpRange 'Microsoft.Network/publicIPPrefixes@2021-02-01' = {
  name: '${prefix}-public-ip-range'
  location: location
  properties: {
    prefixLength: 30
  }
  sku: {
    name: 'Standard'
  }
}

output publicIpRangeId string = publicIpRange.id
