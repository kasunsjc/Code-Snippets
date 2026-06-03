terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azapi" {}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [var.vnet_address_space]
  tags                = var.tags
}

# AKS Subnet
resource "azurerm_subnet" "aks_subnet" {
  name                 = var.aks_subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.aks_subnet_address_prefix]
}

# User Assigned Identity for AKS
resource "azurerm_user_assigned_identity" "aks_identity" {
  name                = "${var.cluster_name}-identity"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

# Role Assignment - Network Contributor for AKS to manage resources in the VNet
resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = azurerm_virtual_network.vnet.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_identity.principal_id
}

# AKS Cluster with App Routing (Istio Gateway API)
resource "azapi_resource" "aks" {
  type      = "Microsoft.ContainerService/managedClusters@2024-09-02-preview"
  name      = var.cluster_name
  location  = azurerm_resource_group.rg.location
  parent_id = azurerm_resource_group.rg.id
  tags      = var.tags

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.aks_identity.id
    ]
  }

  body = {
    properties = {
      dnsPrefix = var.cluster_name
      kubernetesVersion = var.kubernetes_version
      
      # Enable Gateway API
      enableGatewayAPI = true
      
      # Network Profile
      networkProfile = {
        networkPlugin    = "azure"
        networkPolicy    = "azure"
        loadBalancerSku  = "standard"
        serviceCidr      = var.service_cidr
        dnsServiceIP     = var.dns_service_ip
      }
      
      # Agent Pool Profile
      agentPoolProfiles = [
        {
          name                = "systempool"
          count               = var.system_node_count
          vmSize              = var.system_node_size
          mode                = "System"
          osType              = "Linux"
          osSKU               = "AzureLinux"
          type                = "VirtualMachineScaleSets"
          enableAutoScaling   = true
          minCount            = 1
          maxCount            = 3
          vnetSubnetID        = azurerm_subnet.aks_subnet.id
          maxPods             = 30
        }
      ]
      
      # Ingress Profile - Enable App Routing with Istio
      ingressProfile = {
        webAppRouting = {
          enabled = true
          # Enable Istio-based Gateway API implementation
          istioIngressGateway = {
            enabled = true
          }
        }
      }
      
      # Auto-upgrade channel
      autoUpgradeProfile = {
        upgradeChannel = "stable"
      }
      
      # Monitoring
      azureMonitorProfile = {
        metrics = {
          enabled = true
        }
      }
      
      # Security Profile
      securityProfile = {
        defender = {
          securityMonitoring = {
            enabled = false
          }
        }
      }
    }
    
    sku = {
      name = "Base"
      tier = "Standard"
    }
  }

  depends_on = [
    azurerm_role_assignment.aks_network_contributor
  ]
}
