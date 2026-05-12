using 'main.bicep'

param location          = 'northeurope'
param clusterName       = 'aks-keda-demo'
param kubernetesVersion = '1.35'
param nodeCount         = 2
param nodeVmSize        = 'Standard_D2s_v4'

// Set to your Entra ID Object ID to receive Grafana Admin and AKS RBAC Cluster Admin.
// Retrieve with: az ad signed-in-user show --query id -o tsv
param userId = ''

param tags = {
  Environment: 'Demo'
  Project: 'AKS-KEDA'
  ManagedBy: 'Bicep'
}
