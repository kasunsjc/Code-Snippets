// ============================================================
// AKS with Advanced Container Networking Services (ACNS)
// ============================================================
// Deploys an AKS cluster with:
//   - Azure CNI with overlay mode
//   - Cilium data plane
//   - Advanced Container Networking Services enabled
//   - L7 advanced network policies (includes FQDN filtering)
//   - Azure Managed Prometheus for metrics collection
//   - Azure Managed Grafana for metrics visualization
// ============================================================

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Name of the AKS cluster.')
param clusterName string = 'aks-acns-cluster'

@description('DNS prefix for the AKS cluster.')
param dnsPrefix string = clusterName

@description('Kubernetes version. Must be 1.29 or later for ACNS.')
@minLength(1)
param kubernetesVersion string = '1.30'

@description('Number of nodes in the system node pool.')
@minValue(1)
@maxValue(50)
param nodeCount int = 2

@description('VM size for the system node pool.')
param nodeVmSize string = 'Standard_DS2_v2'

@description('SSH public key for node access. Leave empty to auto-generate.')
param sshPublicKey string = ''

@description('Admin username for AKS nodes.')
param adminUsername string = 'azureuser'

@description('Enable auto-scaling on the system node pool.')
param enableAutoScaling bool = true

@description('Minimum node count when auto-scaling is enabled.')
@minValue(1)
param minNodeCount int = 1

@description('Maximum node count when auto-scaling is enabled.')
@maxValue(100)
param maxNodeCount int = 5

@description('Object ID of the user to assign Grafana Admin role. Leave empty to skip.')
param userId string = ''

// ============================================================
// Azure Monitor Workspace (Managed Prometheus)
// ============================================================
resource prometheus 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: '${clusterName}-prometheus'
  location: location
}

// ============================================================
// Azure Managed Grafana
// ============================================================
resource grafana 'Microsoft.Dashboard/grafana@2023-09-01' = {
  name: take('${clusterName}-gr', 23)
  location: location
  sku: {
    name: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    grafanaIntegrations: {
      azureMonitorWorkspaceIntegrations: [
        {
          azureMonitorWorkspaceResourceId: prometheus.id
        }
      ]
    }
    publicNetworkAccess: 'Enabled'
  }
}

// ============================================================
// Data Collection for Prometheus Metrics
// ============================================================
resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = {
  name: 'MSProm-${location}-${clusterName}'
  location: location
  kind: 'Linux'
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'MSProm-${location}-${clusterName}'
  location: location
  properties: {
    dataCollectionEndpointId: dataCollectionEndpoint.id
    dataSources: {
      prometheusForwarder: [
        {
          name: 'PrometheusDataSource'
          streams: [
            'Microsoft-PrometheusMetrics'
          ]
          labelIncludeFilter: {}
        }
      ]
    }
    destinations: {
      monitoringAccounts: [
        {
          accountResourceId: prometheus.id
          name: 'MonitoringAccount1'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-PrometheusMetrics'
        ]
        destinations: [
          'MonitoringAccount1'
        ]
      }
    ]
  }
}

resource dataCollectionRuleAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: 'MSProm-${location}-${clusterName}'
  scope: aksCluster
  properties: {
    dataCollectionRuleId: dataCollectionRule.id
    description: 'Association of data collection rule for Prometheus metrics scraping.'
  }
}

// ============================================================
// Role Assignments for Grafana → Prometheus
// ============================================================

// Monitoring Reader role
resource monitoringReaderRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
  scope: subscription()
}

// Monitoring Data Reader role
resource monitoringDataReaderRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'b0d8363b-8ddd-447d-831f-62ca05bff136'
  scope: subscription()
}

// Grafana Admin role
resource grafanaAdminRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '22926164-76b3-42b3-bc55-97df8dab3e41'
  scope: subscription()
}

// Allow Grafana to read Prometheus metrics
resource monitoringReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(clusterName, prometheus.name, monitoringReaderRole.id)
  scope: prometheus
  properties: {
    roleDefinitionId: monitoringReaderRole.id
    principalId: grafana.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource monitoringDataReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(clusterName, prometheus.name, monitoringDataReaderRole.id)
  scope: prometheus
  properties: {
    roleDefinitionId: monitoringDataReaderRole.id
    principalId: grafana.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Assign Grafana Admin to the deploying user
resource grafanaAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(userId)) {
  name: guid(clusterName, userId, grafanaAdminRole.id)
  scope: grafana
  properties: {
    roleDefinitionId: grafanaAdminRole.id
    principalId: userId
    principalType: 'User'
  }
}

// ============================================================
// AKS Cluster with ACNS + Azure Monitor Metrics
// ============================================================
resource aksCluster 'Microsoft.ContainerService/managedClusters@2025-01-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: dnsPrefix
    kubernetesVersion: kubernetesVersion
    enableRBAC: true
    azureMonitorProfile: {
      metrics: {
        enabled: true
        kubeStateMetrics: {
          metricLabelsAllowlist: ''
          metricAnnotationsAllowList: ''
        }
      }
    }
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        mode: 'System'
        enableAutoScaling: enableAutoScaling
        minCount: enableAutoScaling ? minNodeCount : null
        maxCount: enableAutoScaling ? maxNodeCount : null
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      advancedNetworking: {
        enabled: true
        observability: {
          enabled: true
        }
        security: {
          enabled: true
        }
      }
    }
    autoUpgradeProfile: {
      upgradeChannel: 'stable'
    }
    linuxProfile: sshPublicKey != '' ? {
      adminUsername: adminUsername
      ssh: {
        publicKeys: [
          {
            keyData: sshPublicKey
          }
        ]
      }
    } : null
  }
}

// ============================================================
// Outputs
// ============================================================

@description('The name of the AKS cluster.')
output clusterName string = aksCluster.name

@description('The resource ID of the AKS cluster.')
output clusterResourceId string = aksCluster.id

@description('The FQDN of the AKS cluster API server.')
output clusterFqdn string = aksCluster.properties.fqdn

@description('The network data plane configured for the cluster.')
output networkDataplane string = aksCluster.properties.networkProfile.networkDataplane

@description('The Grafana dashboard endpoint URL.')
output grafanaEndpoint string = grafana.properties.endpoint

@description('The Azure Monitor workspace (Prometheus) resource ID.')
output prometheusResourceId string = prometheus.id

@description('Command to get cluster credentials.')
output getCredentialsCommand string = 'az aks get-credentials --resource-group ${resourceGroup().name} --name ${aksCluster.name}'
