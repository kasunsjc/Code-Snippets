locals {
  name_prefix = "${var.project}-${var.environment}"
  tags = {
    project     = var.project
    environment = var.environment
    demo        = "aks-github-actions-runners"
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# AKS Automatic manages networking (Azure CNI Overlay + Cilium), the system pool,
# Karpenter node autoprovisioning, Azure RBAC, upgrades and Deployment Safeguards.
# The node resource group name is AKS-generated and cannot be customised.
resource "azurerm_kubernetes_automatic_cluster" "this" {
  name                = "aks-${local.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  # Without hosted_system, AKS Automatic requires a system-assigned identity.
  identity {
    type = "SystemAssigned"
  }

  # Optional: restricting the API to known egress IPs is recommended outside demos.
  dynamic "api_server_access" {
    for_each = length(var.api_server_authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.api_server_authorized_ip_ranges
    }
  }

  tags = local.tags
}

# AKS creates the kubelet identity as "<cluster>-agentpool" in the node resource
# group. azurerm_kubernetes_cluster data sources reject the Automatic SKU, so
# read the identity directly for Azure Files RBAC.
data "azurerm_user_assigned_identity" "kubelet" {
  name                = "${azurerm_kubernetes_automatic_cluster.this.name}-agentpool"
  resource_group_name = basename(azurerm_kubernetes_automatic_cluster.this.node_resource_group_id)
}

resource "azurerm_role_assignment" "deployer" {
  scope                = azurerm_kubernetes_automatic_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_monitor_diagnostic_setting" "control_plane" {
  name                       = "control-plane"
  target_resource_id         = azurerm_kubernetes_automatic_cluster.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "kube-apiserver"
  }
  enabled_log {
    category = "kube-audit-admin"
  }
}

resource "azurerm_storage_account" "runners" {
  name                            = "stgha${substr(sha256("${data.azurerm_client_config.current.subscription_id}/${local.name_prefix}"), 0, 18)}"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_kind                    = "FileStorage"
  account_tier                    = "Premium"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}

resource "azurerm_storage_share" "nuget" {
  name               = "nuget-cache"
  storage_account_id = azurerm_storage_account.runners.id
  quota              = var.cache_share_quota_gib
  access_tier        = "Premium"
  enabled_protocol   = "SMB"
}

# Terraform pre-creates the cache share, so kubelets only need to retrieve the
# SMB key at mount time. Scope the role to this dedicated account.
resource "azurerm_role_assignment" "files_kubelet" {
  scope                = azurerm_storage_account.runners.id
  role_definition_name = "Storage Account Key Operator Service Role"
  principal_id         = data.azurerm_user_assigned_identity.kubelet.principal_id
}
