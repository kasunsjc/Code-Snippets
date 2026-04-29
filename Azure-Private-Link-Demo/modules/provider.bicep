// =============================================================================
// Provider module — publishes an internal service via Azure Private Link Service
// =============================================================================
// Resources:
//   - Provider VNet (10.10.0.0/16)
//       * snet-backend (10.10.1.0/24)  -> backend VMs running nginx
//       * snet-pls     (10.10.2.0/24)  -> Private Link Service NAT (PrivateLinkServiceNetworkPolicies disabled)
//   - 2x Linux VMs (nginx via cloud-init)
//   - Standard Internal Load Balancer (frontend in snet-backend)
//   - Azure Private Link Service in front of the ILB
// =============================================================================

@description('Azure region.')
param location string

@description('Resource name prefix.')
param namePrefix string

@description('Admin username for backend VMs.')
param adminUsername string

@description('Admin password for backend VMs (Azure complexity rules apply).')
@secure()
param adminPassword string

@description('VM size for backend VMs.')
param vmSize string

var providerVnetName = '${namePrefix}-provider-vnet'
var backendSubnetName = 'snet-backend'
var plsSubnetName = 'snet-pls'
var lbName = '${namePrefix}-provider-ilb'
var plsName = '${namePrefix}-pls'
var nsgName = '${namePrefix}-provider-nsg'

// ---------------------------------------------------------------------------
// NSG for the backend subnet — allow HTTP from within the VNet only.
// ---------------------------------------------------------------------------
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-VNet'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Provider VNet with two subnets.
// The PLS subnet REQUIRES privateLinkServiceNetworkPolicies = 'Disabled'.
// ---------------------------------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: providerVnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [ '10.10.0.0/16' ]
    }
    subnets: [
      {
        name: backendSubnetName
        properties: {
          addressPrefix: '10.10.1.0/24'
          networkSecurityGroup: { id: nsg.id }
        }
      }
      {
        name: plsSubnetName
        properties: {
          addressPrefix: '10.10.2.0/24'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource backendSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  parent: vnet
  name: backendSubnetName
}

resource plsSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  parent: vnet
  name: plsSubnetName
}

// ---------------------------------------------------------------------------
// Standard Internal Load Balancer (frontend = static IP in backend subnet)
// ---------------------------------------------------------------------------
var lbFrontendIp = '10.10.1.10'

resource lb 'Microsoft.Network/loadBalancers@2024-01-01' = {
  name: lbName
  location: location
  sku: { name: 'Standard' }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'fe-internal'
        properties: {
          subnet: { id: backendSubnet.id }
          privateIPAddress: lbFrontendIp
          privateIPAllocationMethod: 'Static'
        }
      }
    ]
    backendAddressPools: [
      { name: 'bep-nginx' }
    ]
    probes: [
      {
        name: 'probe-http'
        properties: {
          protocol: 'Tcp'
          port: 80
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'rule-http'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'fe-internal')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'bep-nginx')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'probe-http')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// 2x backend Linux VMs running nginx (installed via cloud-init custom data).
// Each VM displays its hostname so consumers can see load-balancing.
// ---------------------------------------------------------------------------
var cloudInit = '''
#cloud-config
package_update: true
packages:
  - nginx
runcmd:
  - echo "<h1>Hello from $(hostname) — provider backend</h1>" > /var/www/html/index.html
  - systemctl enable nginx
  - systemctl restart nginx
'''

resource nics 'Microsoft.Network/networkInterfaces@2024-01-01' = [for i in range(0, 2): {
  name: '${namePrefix}-be-nic-${i}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipcfg'
        properties: {
          subnet: { id: backendSubnet.id }
          privateIPAllocationMethod: 'Dynamic'
          loadBalancerBackendAddressPools: [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'bep-nginx')
            }
          ]
        }
      }
    ]
  }
  dependsOn: [ lb ]
}]

resource backendVMs 'Microsoft.Compute/virtualMachines@2024-07-01' = [for i in range(0, 2): {
  name: '${namePrefix}-be-vm-${i}'
  location: location
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: '${namePrefix}-be-${i}'
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(cloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [
        { id: nics[i].id }
      ]
    }
  }
}]

// ---------------------------------------------------------------------------
// Azure Private Link Service — exposes the ILB frontend over a private
// endpoint. The PLS NAT IPs are allocated from snet-pls.
// ---------------------------------------------------------------------------
resource pls 'Microsoft.Network/privateLinkServices@2024-01-01' = {
  name: plsName
  location: location
  properties: {
    enableProxyProtocol: false
    visibility: {
      // 'subscriptions' restricts who can connect. '*' = any authorised subscription.
      subscriptions: [ '*' ]
    }
    autoApproval: {
      // Auto-approve PE connections from these subscriptions (this one).
      subscriptions: [ subscription().subscriptionId ]
    }
    loadBalancerFrontendIpConfigurations: [
      {
        id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'fe-internal')
      }
    ]
    ipConfigurations: [
      {
        name: 'pls-natip'
        properties: {
          subnet: { id: plsSubnet.id }
          privateIPAllocationMethod: 'Dynamic'
          primary: true
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output vnetName string = vnet.name
output vnetId string = vnet.id
output lbFrontendIp string = lbFrontendIp
output privateLinkServiceId string = pls.id
output privateLinkServiceAlias string = pls.properties.alias
