resource "azurerm_kubernetes_cluster" "this" {
  name                      = var.cluster_name
  location                  = var.location
  resource_group_name       = var.resource_group_name
  node_resource_group       = var.node_resource_group
  dns_prefix                = var.cluster_name
  kubernetes_version        = var.kubernetes_version
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  azure_policy_enabled      = true
  local_account_disabled    = false
  sku_tier                  = "Standard"
  tags                      = var.tags

  default_node_pool {
    name         = "system"
    vm_size      = var.node_vm_size
    node_count   = var.node_count
    os_disk_type = "Ephemeral"
    os_sku       = "AzureLinux"
    max_pods     = 60
    type         = "VirtualMachineScaleSets"
    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
  }

  # Azure NGINX add-on (Application Routing).
  web_app_routing {
    dns_zone_ids = [var.dns_zone_id]
  }

  # Secrets Store CSI Driver with the Azure Key Vault provider.
  # Required for App Routing to mount Key Vault certificates as TLS secrets.
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }
}

# --- Additional user node pool ------------------------------------------------

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = var.user_node_pool_name
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.user_node_pool_vm_size
  node_count            = var.user_node_pool_node_count
  os_disk_type          = "Ephemeral"
  os_sku                = "AzureLinux"
  max_pods              = 60
  mode                  = "User"
  tags                  = var.tags

  upgrade_settings {
    max_surge = "33%"
  }
}
