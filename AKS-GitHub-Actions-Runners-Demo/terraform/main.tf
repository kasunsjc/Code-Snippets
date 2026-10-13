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
    type = "SystemAssigned"
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

  tags = local.tags
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
