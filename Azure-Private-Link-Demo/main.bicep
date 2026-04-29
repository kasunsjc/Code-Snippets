// =============================================================================
// Azure Private Link Service + Private Endpoint — Enterprise Demo
// =============================================================================
// This template provisions two completely isolated VNets to mirror an
// enterprise scenario where a "Provider" team publishes an internal service
// and a "Consumer" team in another VNet/subscription consumes it privately
// via Azure Private Link — without VNet peering, public IPs, or VPN.
//
// It also deploys an Azure Storage Account with a Private Endpoint to
// demonstrate Private Endpoint usage against a 1st-party PaaS service.
// =============================================================================

targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Short prefix used to name resources (3-8 lower-case chars).')
@minLength(3)
@maxLength(8)
param namePrefix string = 'plkdemo'

@description('Admin username for the Linux VMs.')
param adminUsername string = 'azureuser'

@description('Admin password for the Linux VMs. Must satisfy Azure complexity rules: 12-72 chars, with 3 of {lowercase, uppercase, digit, special}.')
@secure()
@minLength(12)
@maxLength(72)
param adminPassword string

@description('VM size for jumpbox and backend VMs.')
param vmSize string = 'Standard_B2s'

@description('Source IP/CIDR allowed to SSH to the jumpbox. Recommended: your public IP /32. Default: Internet (lab only).')
param allowedSshSourceIp string = 'Internet'

// ----- Provider side --------------------------------------------------------
module provider 'modules/provider.bicep' = {
  name: 'provider-deploy'
  params: {
    location: location
    namePrefix: namePrefix
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
  }
}

// ----- Consumer side --------------------------------------------------------
module consumer 'modules/consumer.bicep' = {
  name: 'consumer-deploy'
  params: {
    location: location
    namePrefix: namePrefix
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
    allowedSshSourceIp: allowedSshSourceIp
    privateLinkServiceId: provider.outputs.privateLinkServiceId
  }
}

// ----- PaaS Private Endpoint scenario (Storage) -----------------------------
module storage 'modules/storage-pe.bicep' = {
  name: 'storage-pe-deploy'
  params: {
    location: location
    namePrefix: namePrefix
    consumerVnetId: consumer.outputs.vnetId
    consumerPeSubnetId: consumer.outputs.peSubnetId
  }
}

// ----- Outputs --------------------------------------------------------------
output providerVnetName string = provider.outputs.vnetName
output providerLoadBalancerFrontendIp string = provider.outputs.lbFrontendIp
output privateLinkServiceId string = provider.outputs.privateLinkServiceId
output privateLinkServiceAlias string = provider.outputs.privateLinkServiceAlias

output consumerVnetName string = consumer.outputs.vnetName
output consumerJumpboxPublicIp string = consumer.outputs.jumpboxPublicIp
output consumerPrivateEndpointName string = consumer.outputs.privateEndpointName
output providerDnsZoneName string = consumer.outputs.providerDnsZoneName
output providerHostname string = consumer.outputs.providerHostname
output providerFqdn string = consumer.outputs.providerFqdn

output storageAccountName string = storage.outputs.storageAccountName
output storagePrivateEndpointFqdn string = storage.outputs.privateEndpointFqdn
