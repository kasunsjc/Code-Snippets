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

resource "azurerm_user_assigned_identity" "cluster" {
  name                = "id-${local.name_prefix}-cluster"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

# AKS Automatic manages networking (Azure CNI Overlay + Cilium), the system pool,
# Karpenter node autoprovisioning, Azure RBAC, upgrades and Deployment Safeguards.
# The node resource group name is AKS-generated and cannot be customised.
resource "azurerm_kubernetes_automatic_cluster" "this" {
  name                = "aks-${local.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  api_server_access {
    authorized_ip_ranges = var.api_server_authorized_ip_ranges
  }

  tags = local.tags
}

# Automatic creates the kubelet identity; read it back for Azure Files RBAC.
data "azurerm_kubernetes_cluster" "this" {
  name                = azurerm_kubernetes_automatic_cluster.this.name
  resource_group_name = azurerm_resource_group.this.name
  depends_on          = [azurerm_kubernetes_automatic_cluster.this]
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

# The controller provisions shares; kubelets retrieve SMB keys at mount time.
# Scope both identities to this dedicated account, not the subscription.
resource "azurerm_role_assignment" "files_controller" {
  scope                = azurerm_storage_account.runners.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
}

resource "azurerm_role_assignment" "files_kubelet" {
  scope                = azurerm_storage_account.runners.id
  role_definition_name = "Storage Account Key Operator Service Role"
  principal_id         = data.azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}
