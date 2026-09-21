# A pre-created identity lets us grant Network Contributor on the subnet before
# the cluster exists - a SystemAssigned identity can't be granted roles until
# after cluster creation, which is too late for a bring-your-own-subnet cluster.
resource "azurerm_user_assigned_identity" "aks" {
  name                = "id-aks-${var.cluster_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = var.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  node_resource_group = var.node_resource_group_name
  tags                = var.tags

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  private_cluster_enabled = true
  private_dns_zone_id     = "System"

  default_node_pool {
    name                         = "system"
    vm_size                      = "Standard_D4s_v5"
    node_count                   = 3
    os_disk_size_gb              = 128
    vnet_subnet_id               = var.vnet_subnet_id
    auto_scaling_enabled         = true
    min_count                    = 3
    max_count                    = 6
    zones                        = ["1", "2", "3"]
    only_critical_addons_enabled = true

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
  }

  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  monitor_metrics {}

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  depends_on = [azurerm_role_assignment.aks_network_contributor]
}

resource "azurerm_kubernetes_cluster_node_pool" "harbor" {
  name                  = "harbor"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = "Standard_D4s_v5"
  node_count            = 3
  vnet_subnet_id        = var.vnet_subnet_id
  auto_scaling_enabled  = true
  min_count             = 3
  max_count             = 6
  zones                 = ["1", "2", "3"]
  os_disk_size_gb       = 128

  upgrade_settings {
    max_surge = "10%"
  }
}

resource "azurerm_role_assignment" "cluster_admin" {
  count                = var.user_object_id == "" ? 0 : 1
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.user_object_id
}
