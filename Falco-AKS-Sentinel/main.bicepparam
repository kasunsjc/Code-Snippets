// ========================================
// Parameters file for Falco AKS Demo
// ========================================

using './main.bicep'

// Basic Configuration
param aksClusterName = 'aks-falco-demo'
param logAnalyticsWorkspaceName = 'law-falco-demo-1'
param location = 'eastus'

// AKS Configuration
param kubernetesVersion = '1.33'
param nodeVmSize = 'Standard_DS2_v2'
param nodeCount = 3

// Feature Flags
param enableSentinel = true

// Azure AD Configuration
// This will be set dynamically by the deployment script
param aksAdminPrincipalId = ''

// Tags
param tags = {
  Environment: 'Demo'
  Purpose: 'Falco-Security-Audit'
  ManagedBy: 'Bicep'
  Project: 'Festive-Tech-Calendar'
  Demo: 'Falco-Sentinel-Integration'
}
