resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  node_resource_group = var.node_resource_group_name
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                 = "systempool"
    vm_size              = var.node_vm_size
    type                 = "VirtualMachineScaleSets"
    max_pods             = 110
    auto_scaling_enabled = var.enable_node_autoscaling
    min_count            = var.enable_node_autoscaling ? var.node_min_count : null
    max_count            = var.enable_node_autoscaling ? var.node_max_count : null
    node_count           = var.enable_node_autoscaling ? null : var.node_count

    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
  }

  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  monitor_metrics {
    annotations_allowed = "*"
    labels_allowed      = "*"
  }

  workload_autoscaler_profile {
    keda_enabled = true
  }
}

resource "azurerm_role_assignment" "aks_cluster_admin" {
  count                = var.user_object_id == "" ? 0 : 1
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.user_object_id
}
