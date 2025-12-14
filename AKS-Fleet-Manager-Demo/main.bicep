// AKS Fleet Manager Demo - Main Deployment
// This template deploys an AKS Fleet Manager with multiple member clusters
targetScope = 'subscription'

@description('Azure region for the resource group and Fleet Manager')
param location string = 'eastus'

@description('Azure region for member cluster 1')
param memberCluster1Location string = 'eastus'

@description('Azure region for member cluster 2')
param memberCluster2Location string = 'westus'

@description('Environment name for resource naming')
param environmentName string = 'demo'

@description('Resource group name')
param resourceGroupName string = 'rg-aks-fleet-${environmentName}'

@description('Enable hub cluster for Fleet Manager')
param enableHubCluster bool = true

@description('Principal ID (Object ID) to assign Fleet Manager admin role. Leave empty to use current user.')
param principalId string = ''

@description('Principal type for RBAC assignment')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param principalType string = 'User'

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'Demo'
  Project: 'AKS-Fleet-Manager'
  ManagedBy: 'Bicep'
}

// Variables
var fleetName = 'fleet-${environmentName}-${uniqueString(subscription().subscriptionId, resourceGroupName)}'
var memberCluster1Name = 'aks-member1-${environmentName}'
var memberCluster2Name = 'aks-member2-${environmentName}'
var logAnalyticsWorkspaceName = 'law-fleet-${environmentName}-${uniqueString(subscription().subscriptionId, resourceGroupName)}'

// Create Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// Log Analytics Workspace
module logAnalytics 'modules/log-analytics.bicep' = {
  scope: rg
  name: 'log-analytics-deployment'
  params: {
    workspaceName: logAnalyticsWorkspaceName
    location: location
    tags: tags
  }
}

// Virtual Networks for member clusters
module vnet1 'modules/vnet.bicep' = {
  scope: rg
  name: 'vnet1-deployment'
  params: {
    vnetName: 'vnet-member1-${environmentName}'
    location: memberCluster1Location
    addressPrefix: '10.1.0.0/16'
    aksSubnetPrefix: '10.1.0.0/22'
    tags: tags
  }
}

module vnet2 'modules/vnet.bicep' = {
  scope: rg
  name: 'vnet2-deployment'
  params: {
    vnetName: 'vnet-member2-${environmentName}'
    location: memberCluster2Location
    addressPrefix: '10.2.0.0/16'
    aksSubnetPrefix: '10.2.0.0/22'
    tags: tags
  }
}

// AKS Member Cluster 1
module aksCluster1 'modules/aks-member.bicep' = {
  scope: rg
  name: 'aks-cluster1-deployment'
  params: {
    clusterName: memberCluster1Name
    location: memberCluster1Location
    subnetId: vnet1.outputs.aksSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: union(tags, { MemberCluster: 'cluster1', Region: memberCluster1Location })
  }
}

// AKS Member Cluster 2
module aksCluster2 'modules/aks-member.bicep' = {
  scope: rg
  name: 'aks-cluster2-deployment'
  params: {
    clusterName: memberCluster2Name
    location: memberCluster2Location
    subnetId: vnet2.outputs.aksSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: union(tags, { MemberCluster: 'cluster2', Region: memberCluster2Location })
  }
}

// AKS Fleet Manager
module fleetManager 'modules/fleet-manager.bicep' = {
  scope: rg
  name: 'fleet-manager-deployment'
  params: {
    fleetName: fleetName
    location: location
    enableHubCluster: enableHubCluster
    tags: tags
  }
}

// Fleet Membership for Cluster 1
module fleetMember1 'modules/fleet-member.bicep' = {
  scope: rg
  name: 'fleet-member1-deployment'
  params: {
    fleetName: fleetManager.outputs.fleetName
    memberClusterName: memberCluster1Name
    memberClusterResourceId: aksCluster1.outputs.clusterResourceId
    memberName: '${memberCluster1Name}-member'
  }
}

// Fleet Membership for Cluster 2
module fleetMember2 'modules/fleet-member.bicep' = {
  scope: rg
  name: 'fleet-member2-deployment'
  params: {
    fleetName: fleetManager.outputs.fleetName
    memberClusterName: memberCluster2Name
    memberClusterResourceId: aksCluster2.outputs.clusterResourceId
    memberName: '${memberCluster2Name}-member'
  }
}

// Fleet RBAC Role Assignment (only if principalId is provided)
module fleetRbac 'modules/fleet-rbac.bicep' = if (!empty(principalId)) {
  scope: rg
  name: 'fleet-rbac-deployment'
  params: {
    fleetName: fleetManager.outputs.fleetName
    principalId: principalId
    principalType: principalType
  }
}

// Outputs
output resourceGroupName string = rg.name
output fleetName string = fleetManager.outputs.fleetName
output fleetResourceId string = fleetManager.outputs.fleetResourceId
output fleetHubKubeConfigCommand string = enableHubCluster ? 'az fleet get-credentials --resource-group ${rg.name} --name ${fleetManager.outputs.fleetName}' : 'N/A - Hub cluster not enabled'
output memberCluster1Name string = aksCluster1.outputs.clusterName
output memberCluster2Name string = aksCluster2.outputs.clusterName
output memberCluster1ResourceId string = aksCluster1.outputs.clusterResourceId
output memberCluster2ResourceId string = aksCluster2.outputs.clusterResourceId
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
