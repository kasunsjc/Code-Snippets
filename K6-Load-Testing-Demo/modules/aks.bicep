// K6 Load Testing Demo — AKS Module

@description('AKS cluster name')
param clusterName string

@description('Azure region')
param location string

@description('Object ID of the user to receive AKS RBAC Cluster Admin role')
param userId string = ''

@description('Tags applied to all resources')
param tags object

// ========== AKS Cluster ==========

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-07-02-preview' = {
  name: clusterName
  location: location
  tags: tags
  sku: {
    name: 'Base'
    tier: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // Custom node resource group name per workspace convention
    nodeResourceGroup: 'rg-${clusterName}-nodes'
    dnsPrefix: clusterName
    agentPoolProfiles: [
      {
        name: 'systempool'
        mode: 'System'
        count: 3
        vmSize: 'Standard_D4s_v5'
        osType: 'Linux'
        osDiskSizeGB: 128
        maxPods: 110
        type: 'VirtualMachineScaleSets'
      }
    ]
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
    disableLocalAccounts: true
  }
}

// ========== Role Assignments ==========

resource aksRbacClusterAdminRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b'
  scope: subscription()
}

resource aksClusterAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(userId)) {
  name: guid(clusterName, userId, aksRbacClusterAdminRole.id)
  scope: aksCluster
  properties: {
    roleDefinitionId: aksRbacClusterAdminRole.id
    principalId: userId
    principalType: 'User'
  }
}

// ========== Outputs ==========

output aksClusterName string = aksCluster.name
