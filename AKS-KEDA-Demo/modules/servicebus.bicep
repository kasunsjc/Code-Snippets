// ============================================================
// Module: Azure Service Bus Namespace + Queue
//
// Used by KEDA Scenario 02 (Service Bus scaler).
// ============================================================

@description('Service Bus namespace name (globally unique).')
param namespaceName string

@description('Azure region.')
param location string

@description('Name of the Service Bus queue for KEDA demo.')
param queueName string = 'keda-demo-queue'

@description('Resource tags.')
param tags object = {}

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
  }
}

resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: queueName
  properties: {
    maxDeliveryCount: 10
  }
}

// ============================================================
// Outputs
// ============================================================

output namespaceName string = serviceBusNamespace.name
output namespaceId string = serviceBusNamespace.id
output queueName string = serviceBusQueue.name
