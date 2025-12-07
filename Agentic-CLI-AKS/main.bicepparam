// Parameters file for Agentic CLI AKS Demo deployment
using './main.bicep'

// Resource naming
param namePrefix = 'aksagent'
param environment = 'dev'

// Location
param location = 'eastus'

// AKS Configuration
param kubernetesVersion = '1.31.2'
param nodeCount = 2
param nodeVmSize = 'Standard_D4s_v3'

// OpenAI Configuration
param openAiModelName = 'gpt-4o'
param openAiModelVersion = '2024-08-06'
param openAiModelCapacity = 150

// Monitoring
param enableMonitoring = true

// Tags
param tags = {
  Environment: 'dev'
  Project: 'Agentic-CLI-AKS'
  ManagedBy: 'Bicep'
  Owner: 'DevOps'
}
