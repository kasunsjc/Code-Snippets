@description('The location for the AKS cluster')
param location string

@description('The base name for resources')
param baseName string

@description('The environment name')
param environmentName string

@description('Tags to apply to resources')
param tags object

@description('Kubernetes version')
param kubernetesVersion string

@description('Number of nodes in the default node pool')
param nodeCount int

@description('VM size for nodes')
param nodeVmSize string

@description('Maximum number of pods per node')
param maxPods int

@description('Subnet ID for AKS')
param subnetId string

@description('Log Analytics workspace ID')
param logAnalyticsWorkspaceId string

@description('Enable monitoring')
param enableMonitoring bool

@description('Network plugin')
param networkPlugin string

@description('Network policy')
param networkPolicy string

@description('Azure Monitor Workspace ID for Prometheus')
param azureMonitorWorkspaceId string = ''

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: 'aks-${baseName}-${environmentName}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: '${baseName}-${environmentName}'
    enableRBAC: true
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
        mode: 'System'
        maxPods: maxPods
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: subnetId
        enableAutoScaling: true
        minCount: 3
        maxCount: 5
      }
    ]
    networkProfile: {
      networkPlugin: networkPlugin
      networkPolicy: networkPolicy
      serviceCidr: '172.16.0.0/16'
      dnsServiceIP: '172.16.0.10'
    }
    addonProfiles: {
      omsagent: {
        enabled: enableMonitoring
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
    }
    azureMonitorProfile: !empty(azureMonitorWorkspaceId) ? {
      metrics: {
        enabled: true
        kubeStateMetrics: {
          metricLabelsAllowlist: ''
          metricAnnotationsAllowList: ''
        }
      }
    } : null
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
  }
}

output clusterName string = aksCluster.name
output clusterId string = aksCluster.id
output clusterFqdn string = aksCluster.properties.fqdn
output clusterIdentityPrincipalId string = aksCluster.identity.principalId
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL
