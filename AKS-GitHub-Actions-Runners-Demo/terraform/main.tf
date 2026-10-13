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

resource "azurerm_user_assigned_identity" "kubelet" {
  name                = "id-${local.name_prefix}-kubelet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "kubelet_operator" {
  scope                = azurerm_user_assigned_identity.kubelet.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
}

resource "azurerm_kubernetes_cluster" "this" {
  name                              = "aks-${local.name_prefix}"
  location                          = azurerm_resource_group.this.location
  resource_group_name               = azurerm_resource_group.this.name
  node_resource_group               = "rg-${local.name_prefix}-nodes"
  dns_prefix                        = local.name_prefix
  kubernetes_version                = var.kubernetes_version
  sku_tier                          = "Free"
  role_based_access_control_enabled = true
  local_account_disabled            = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  automatic_upgrade_channel         = "patch"
  node_os_upgrade_channel           = "NodeImage"

  node_provisioning_profile {
    mode = "Manual"
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.node_vm_size
    node_count                   = 1
    os_sku                       = "AzureLinux3"
    only_critical_addons_enabled = true
    temporary_name_for_rotation  = "systmp"
    node_labels = {
      workload = "system"
    }
    upgrade_settings {
      max_surge = "1"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.kubelet.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.kubelet.id
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  api_server_access_profile {
    authorized_ip_ranges = var.api_server_authorized_ip_ranges
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.this.id
    msi_auth_for_monitoring_enabled = true
  }

  storage_profile {
    file_driver_enabled = true
  }

  tags       = local.tags
  depends_on = [azurerm_role_assignment.kubelet_operator]
}

resource "azurerm_kubernetes_cluster_node_pool" "runners" {
  name                        = "runners"
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.this.id
  vm_size                     = var.node_vm_size
  mode                        = "User"
  os_sku                      = "AzureLinux3"
  os_disk_size_gb             = 128
  auto_scaling_enabled        = true
  min_count                   = 0
  max_count                   = var.runner_node_max_count
  node_count                  = 0
  temporary_name_for_rotation = "runrtmp"
  node_taints                 = ["workload=github-actions:NoSchedule"]
  node_labels = {
    workload = "github-actions"
  }
  upgrade_settings {
    max_surge = "1"
  }
  tags = local.tags

  lifecycle {
    ignore_changes = [node_count]
  }
}

resource "azurerm_role_assignment" "deployer" {
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_monitor_diagnostic_setting" "control_plane" {
  name                       = "control-plane"
  target_resource_id         = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "kube-apiserver"
  }
  enabled_log {
    category = "kube-audit-admin"
  }
  enabled_log {
    category = "cluster-autoscaler"
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
  principal_id         = azurerm_user_assigned_identity.kubelet.principal_id
}
