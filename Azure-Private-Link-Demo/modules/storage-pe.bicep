// =============================================================================
// Storage Private Endpoint module
// =============================================================================
// Demonstrates the second classic enterprise pattern: connecting privately to
// a 1st-party PaaS service (Azure Storage Blob) via Private Endpoint, with a
// Private DNS Zone so that the public FQDN resolves to a private IP.
// =============================================================================

@description('Azure region.')
param location string

@description('Resource name prefix.')
param namePrefix string

@description('Consumer VNet resource ID (DNS zone is linked to it).')
param consumerVnetId string

@description('Consumer PE subnet ID.')
param consumerPeSubnetId string

var storageAccountName = toLower('${replace(namePrefix, '-', '')}st${uniqueString(resourceGroup().id)}')
var blobPrivateDnsZone = 'privatelink.blob.${environment().suffixes.storage}'
var pePaasName = '${namePrefix}-pe-storage'

// ---------------------------------------------------------------------------
// Storage account with public network access disabled (defence in depth).
// ---------------------------------------------------------------------------
resource storage 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: storageAccountName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
  }
}

// ---------------------------------------------------------------------------
// Private DNS Zone for blob endpoints — linked to the consumer VNet so VMs
// auto-resolve <account>.blob.core.windows.net to the PE's private IP.
// ---------------------------------------------------------------------------
resource dnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: blobPrivateDnsZone
  location: 'global'
}

resource dnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZone
  name: '${namePrefix}-consumer-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: consumerVnetId }
  }
}

// ---------------------------------------------------------------------------
// Private Endpoint to the storage account (blob sub-resource).
// ---------------------------------------------------------------------------
resource pe 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: pePaasName
  location: location
  properties: {
    subnet: { id: consumerPeSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'storage-blob-conn'
        properties: {
          privateLinkServiceId: storage.id
          groupIds: [ 'blob' ]
        }
      }
    ]
  }
}

// Wire the PE's NIC IP into the Private DNS Zone so the public FQDN resolves
// privately (this is the "DNS configurations" you see in the Portal).
resource peDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob-config'
        properties: {
          privateDnsZoneId: dnsZone.id
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output storageAccountName string = storage.name
output privateEndpointFqdn string = '${storage.name}.blob.${environment().suffixes.storage}'
