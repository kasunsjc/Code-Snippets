// Main Bicep template for Agentic CLI AKS Demo
// Deploys AKS cluster and Azure OpenAI resources

targetScope = 'resourceGroup'

@description('The Azure region for all resources')
param location string = resourceGroup().location

@description('The name prefix for all resources')
@minLength(3)
@maxLength(10)
param namePrefix string = 'aksagent'

@description('Environment name (dev, test, prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('AKS Kubernetes version')
param kubernetesVersion string = '1.31.2'

@description('AKS node count')
@minValue(1)
@maxValue(10)
param nodeCount int = 2

@description('AKS node VM size')
param nodeVmSize string = 'Standard_D4s_v3'

@description('OpenAI model deployment name')
param openAiModelName string = 'gpt-4o'

@description('OpenAI model version')
param openAiModelVersion string = '2024-08-06'

@description('OpenAI model capacity (TPM in thousands)')
@minValue(1)
@maxValue(1000)
param openAiModelCapacity int = 150

@description('Enable Azure Monitor Container Insights')
param enableMonitoring bool = true

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: 'Agentic-CLI-AKS'
  ManagedBy: 'Bicep'
}

@description('Unique deployment identifier (timestamp)')
param deploymentId string = utcNow('yyyyMMddHHmmss')

// Variables
var uniqueSuffix = uniqueString(resourceGroup().id, deploymentId)
var aksClusterName = '${namePrefix}-aks-${environment}-${uniqueSuffix}'
var openAiName = '${namePrefix}-openai-${environment}-${uniqueSuffix}'
var logAnalyticsName = '${namePrefix}-logs-${environment}-${uniqueSuffix}'
var vnetName = '${namePrefix}-vnet-${environment}'
var acrName = '${namePrefix}acr${environment}${uniqueSuffix}'

// Log Analytics Workspace for AKS monitoring
module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'log-analytics-deployment'
  params: {
    workspaceName: logAnalyticsName
    location: location
    tags: tags
  }
}

// Virtual Network for AKS
module vnet 'modules/vnet.bicep' = {
  name: 'vnet-deployment'
  params: {
    vnetName: vnetName
    location: location
    tags: tags
  }
}

// Azure Container Registry
module acr 'modules/acr.bicep' = {
  name: 'acr-deployment'
  params: {
    acrName: acrName
    location: location
    tags: tags
  }
}

// AKS Cluster
module aks 'modules/aks.bicep' = {
  name: 'aks-deployment'
  params: {
    clusterName: aksClusterName
    location: location
    kubernetesVersion: kubernetesVersion
    nodeCount: nodeCount
    nodeVmSize: nodeVmSize
    subnetId: vnet.outputs.aksSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    enableMonitoring: enableMonitoring
    tags: tags
  }
}

// Azure OpenAI
module openai 'modules/openai.bicep' = {
  name: 'openai-deployment'
  params: {
    openAiName: openAiName
    location: location
    modelName: openAiModelName
    modelVersion: openAiModelVersion
    modelCapacity: openAiModelCapacity
    tags: tags
  }
}

// Role assignment for AKS to pull from ACR
module acrRoleAssignment 'modules/acr-role-assignment.bicep' = {
  name: 'acr-role-assignment'
  params: {
    acrName: acr.outputs.acrName
    aksPrincipalId: aks.outputs.kubeletIdentityObjectId
  }
}

// Outputs
output aksClusterName string = aks.outputs.clusterName
output aksClusterFqdn string = aks.outputs.clusterFqdn
output aksResourceId string = aks.outputs.aksResourceId
output openAiEndpoint string = openai.outputs.endpoint
output openAiName string = openai.outputs.name
output openAiModelDeploymentName string = openai.outputs.modelDeploymentName
output acrLoginServer string = acr.outputs.loginServer
output resourceGroupName string = resourceGroup().name
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
