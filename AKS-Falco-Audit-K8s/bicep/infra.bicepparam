using './infra.bicep'

param location = 'northeurope'
param clusterName = 'falco-audit-k8s'
param logAnalyticsWorkspaceName = 'falco-lw'
param retentionInDays = 30
param contentSolutions = [
  'SecurityInsights'
]

