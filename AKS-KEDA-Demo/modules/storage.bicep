// ============================================================
// Module: Azure Storage Account + Queue
//
// Used by KEDA Scenario 01 (Storage Queue scaler).
// ============================================================

@description('Storage account name (3-24 lowercase alphanumeric, globally unique).')
param storageAccountName string

@description('Azure region.')
param location string

@description('Name of the storage queue for KEDA demo.')
param queueName string = 'keda-demo-queue'

@description('Resource tags.')
param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-04-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2023-04-01' = {
  parent: storageAccount
  name: 'default'
}

resource queue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-04-01' = {
  parent: queueService
  name: queueName
}

// ============================================================
// Outputs
// ============================================================

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output storageQueueName string = queue.name
