// AKS Fleet Manager Demo - Main Deployment
// This template deploys an AKS Fleet Manager with environment-based member clusters
// Dev (2), ACC (2), Prod (2) - one Dev cluster is standalone for fleet connection demo
targetScope = 'subscription'

@description('Azure region for the resource group and Fleet Manager')
param location string = 'westeurope'

@description('Azure region for cluster location 1 (dev-1, acc-1, prod-1)')
param clusterLocation1 string = 'westeurope'

@description('Azure region for cluster location 2 (dev-2, acc-2, prod-2)')
param clusterLocation2 string = 'northeurope'

@description('Environment name for resource naming')
param environmentName string = 'demo'

@description('Resource group name')
param resourceGroupName string = 'rg-aks-fleet-${environmentName}'

@description('Enable hub cluster for Fleet Manager')
param enableHubCluster bool = true

@description('Kubernetes version for Dev clusters')
param devKubernetesVersion string = '1.32.0'

@description('Kubernetes version for ACC clusters')
param accKubernetesVersion string = '1.33.5'

@description('Kubernetes version for Prod clusters')
param prodKubernetesVersion string = '1.32'

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
var devCluster1Name = 'aks-dev-1-${environmentName}'
var devCluster2Name = 'aks-dev-2-${environmentName}'
var accCluster1Name = 'aks-acc-1-${environmentName}'
var accCluster2Name = 'aks-acc-2-${environmentName}'
var prodCluster1Name = 'aks-prod-1-${environmentName}'
var prodCluster2Name = 'aks-prod-2-${environmentName}'
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

// Virtual Networks for clusters
module vnet1 'modules/vnet.bicep' = {
  scope: rg
  name: 'vnet1-deployment'
  params: {
    vnetName: 'vnet-fleet-1-${environmentName}'
    location: clusterLocation1
    addressPrefix: '10.1.0.0/16'
    aksSubnetPrefix: '10.1.0.0/22'
    tags: tags
  }
}

module vnet2 'modules/vnet.bicep' = {
  scope: rg
  name: 'vnet2-deployment'
  params: {
    vnetName: 'vnet-fleet-2-${environmentName}'
    location: clusterLocation2
    addressPrefix: '10.2.0.0/16'
    aksSubnetPrefix: '10.2.0.0/22'
    tags: tags
  }
}

// =============================================
// Dev Clusters
// =============================================

// Dev Cluster 1 (connected to fleet)
module aksDev1 'modules/aks-member.bicep' = {
  scope: rg
  name: 'aks-dev-1-deployment'
  params: {
    clusterName: devCluster1Name
    location: clusterLocation1
    kubernetesVersion: devKubernetesVersion
    subnetId: vnet1.outputs.aksSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: union(tags, { Environment: 'dev', Cluster: 'dev-1', Region: clusterLocation1 })
  }
}

// Dev Cluster 2 (standalone - not connected to fleet initially for demo purposes)
module aksDev2 'modules/aks-member.bicep' = {
  scope: rg
  name: 'aks-dev-2-deployment'
  params: {
    clusterName: devCluster2Name
    location: clusterLocation2
    kubernetesVersion: devKubernetesVersion
    subnetId: vnet2.outputs.aksSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: union(tags, { Environment: 'dev', Cluster: 'dev-2-standalone', Region: clusterLocation2, Standalone: 'true' })
  }
}

// =============================================
// ACC (Acceptance) Clusters
// =============================================

// ACC Cluster 1
module aksAcc1 'modules/aks-member.bicep' = {
  scope: rg
  name: 'aks-acc-1-deployment'
  params: {
    clusterName: accCluster1Name
    location: clusterLocation1
    kubernetesVersion: accKubernetesVersion
    subnetId: vnet1.outputs.aksSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: union(tags, { Environment: 'acc', Cluster: 'acc-1', Region: clusterLocation1 })
  }
}

// ACC Cluster 2
module aksAcc2 'modules/aks-member.bicep' = {
  scope: rg
  name: 'aks-acc-2-deployment'
  params: {
    clusterName: accCluster2Name
    location: clusterLocation2
    kubernetesVersion: accKubernetesVersion
    subnetId: vnet2.outputs.aksSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: union(tags, { Environment: 'acc', Cluster: 'acc-2', Region: clusterLocation2 })
  }
}

// =============================================
// Prod Clusters
// =============================================

// Prod Cluster 1
module aksProd1 'modules/aks-member.bicep' = {
  scope: rg
  name: 'aks-prod-1-deployment'
  params: {
    clusterName: prodCluster1Name
    location: clusterLocation1
    kubernetesVersion: prodKubernetesVersion
    subnetId: vnet1.outputs.aksSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: union(tags, { Environment: 'prod', Cluster: 'prod-1', Region: clusterLocation1 })
  }
}

// Prod Cluster 2
module aksProd2 'modules/aks-member.bicep' = {
  scope: rg
  name: 'aks-prod-2-deployment'
  params: {
    clusterName: prodCluster2Name
    location: clusterLocation2
    kubernetesVersion: prodKubernetesVersion
    subnetId: vnet2.outputs.aksSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: union(tags, { Environment: 'prod', Cluster: 'prod-2', Region: clusterLocation2 })
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

// =============================================
// Fleet Memberships (dev-2 is excluded - standalone)
// =============================================

// Fleet Membership for Dev Cluster 1
module fleetMemberDev1 'modules/fleet-member.bicep' = {
  scope: rg
  name: 'fleet-member-dev-1-deployment'
  dependsOn: [
    fleetManager
    aksDev1
  ]
  params: {
    fleetName: fleetManager.outputs.fleetName
    memberClusterName: devCluster1Name
    memberClusterResourceId: aksDev1.outputs.clusterResourceId
    memberName: '${devCluster1Name}-member'
  }
}

// NOTE: Dev Cluster 2 is intentionally NOT connected to the fleet
// Use connect-cluster.sh to demo adding it to the fleet

// Fleet Membership for ACC Cluster 1
module fleetMemberAcc1 'modules/fleet-member.bicep' = {
  scope: rg
  name: 'fleet-member-acc-1-deployment'
  dependsOn: [
    fleetManager
    aksAcc1
  ]
  params: {
    fleetName: fleetManager.outputs.fleetName
    memberClusterName: accCluster1Name
    memberClusterResourceId: aksAcc1.outputs.clusterResourceId
    memberName: '${accCluster1Name}-member'
  }
}

// Fleet Membership for ACC Cluster 2
module fleetMemberAcc2 'modules/fleet-member.bicep' = {
  scope: rg
  name: 'fleet-member-acc-2-deployment'
  dependsOn: [
    fleetManager
    aksAcc2
  ]
  params: {
    fleetName: fleetManager.outputs.fleetName
    memberClusterName: accCluster2Name
    memberClusterResourceId: aksAcc2.outputs.clusterResourceId
    memberName: '${accCluster2Name}-member'
  }
}

// Fleet Membership for Prod Cluster 1
module fleetMemberProd1 'modules/fleet-member.bicep' = {
  scope: rg
  name: 'fleet-member-prod-1-deployment'
  dependsOn: [
    fleetManager
    aksProd1
  ]
  params: {
    fleetName: fleetManager.outputs.fleetName
    memberClusterName: prodCluster1Name
    memberClusterResourceId: aksProd1.outputs.clusterResourceId
    memberName: '${prodCluster1Name}-member'
  }
}

// Fleet Membership for Prod Cluster 2
module fleetMemberProd2 'modules/fleet-member.bicep' = {
  scope: rg
  name: 'fleet-member-prod-2-deployment'
  dependsOn: [
    fleetManager
    aksProd2
  ]
  params: {
    fleetName: fleetManager.outputs.fleetName
    memberClusterName: prodCluster2Name
    memberClusterResourceId: aksProd2.outputs.clusterResourceId
    memberName: '${prodCluster2Name}-member'
  }
}

// Fleet RBAC Role Assignment (only if principalId is provided)
module fleetRbac 'modules/fleet-rbac.bicep' = if (!empty(principalId)) {
  scope: rg
  name: 'fleet-rbac-deployment'
  dependsOn: [
    fleetManager
  ]
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

// Dev Cluster Outputs
output devCluster1Name string = aksDev1.outputs.clusterName
output devCluster2Name string = aksDev2.outputs.clusterName
output devCluster1ResourceId string = aksDev1.outputs.clusterResourceId
output devCluster2ResourceId string = aksDev2.outputs.clusterResourceId

// ACC Cluster Outputs
output accCluster1Name string = aksAcc1.outputs.clusterName
output accCluster2Name string = aksAcc2.outputs.clusterName
output accCluster1ResourceId string = aksAcc1.outputs.clusterResourceId
output accCluster2ResourceId string = aksAcc2.outputs.clusterResourceId

// Prod Cluster Outputs
output prodCluster1Name string = aksProd1.outputs.clusterName
output prodCluster2Name string = aksProd2.outputs.clusterName
output prodCluster1ResourceId string = aksProd1.outputs.clusterResourceId
output prodCluster2ResourceId string = aksProd2.outputs.clusterResourceId

output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
