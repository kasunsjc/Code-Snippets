locals {
  name_prefix = "${var.project}-demo"
  tags = {
    project     = var.project
    environment = "demo"
    managed_by  = "terraform"
  }
  tables = {
    baseline_audit      = { workspace = "baseline", table = "AKSAudit" }
    baseline_control    = { workspace = "baseline", table = "AKSControlPlane" }
    transformed_audit   = { workspace = "transformed", table = "AKSAudit" }
    transformed_control = { workspace = "transformed", table = "AKSControlPlane" }
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_log_analytics_workspace" "this" {
  for_each = toset(["baseline", "transformed"])

  name                = "log-${local.name_prefix}-${each.key}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags

  lifecycle {
    # The post-creation AzAPI update owns this property to avoid a workspace/DCR cycle.
    ignore_changes = [data_collection_rule_id]
  }
}

resource "azapi_resource" "table" {
  for_each = local.tables

  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = each.value.table
  parent_id = azurerm_log_analytics_workspace.this[each.value.workspace].id
  body = {
    properties = {
      plan            = "Analytics"
      retentionInDays = 30
      schema = {
        name = each.value.table
      }
    }
  }
}

resource "azurerm_monitor_data_collection_rule" "transform" {
  name                = "dcr-${local.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  kind                = "WorkspaceTransforms"
  tags                = local.tags

  destinations {
    log_analytics {
      name                  = "transformed"
      workspace_resource_id = azurerm_log_analytics_workspace.this["transformed"].id
    }
  }

  dynamic "data_flow" {
    for_each = toset(["AKSAudit", "AKSControlPlane"])
    content {
      streams       = ["Microsoft-Table-${data_flow.value}"]
      destinations  = ["transformed"]
      transform_kql = trimspace(file("${path.module}/../transforms/${data_flow.value}.kql"))
    }
  }

  depends_on = [azapi_resource.table]
}

resource "azapi_update_resource" "workspace_transform" {
  type        = "Microsoft.OperationalInsights/workspaces@2022-10-01"
  resource_id = azurerm_log_analytics_workspace.this["transformed"].id
  body = {
    properties = {
      defaultDataCollectionRuleResourceId = azurerm_monitor_data_collection_rule.transform.id
    }
  }
}

resource "azapi_resource_action" "unlink_workspace_transform" {
  type        = "Microsoft.OperationalInsights/workspaces@2022-10-01"
  resource_id = azurerm_log_analytics_workspace.this["transformed"].id
  method      = "PATCH"
  when        = "destroy"
  body = {
    properties = {
      defaultDataCollectionRuleResourceId = ""
    }
  }

  depends_on = [azapi_update_resource.workspace_transform]
}

resource "azurerm_kubernetes_cluster" "this" {
  name                              = "aks-${local.name_prefix}"
  location                          = azurerm_resource_group.this.location
  resource_group_name               = azurerm_resource_group.this.name
  node_resource_group               = "rg-${local.name_prefix}-nodes"
  dns_prefix                        = "aks-${local.name_prefix}"
  role_based_access_control_enabled = true
  tags                              = local.tags

  default_node_pool {
    name       = "system"
    node_count = 1
    vm_size    = var.node_vm_size
    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  api_server_access_profile {
    authorized_ip_ranges = var.api_server_authorized_ip_ranges
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    load_balancer_sku   = "standard"
  }
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  for_each = azurerm_log_analytics_workspace.this

  name                           = "control-plane-${each.key}"
  target_resource_id             = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id     = each.value.id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = toset(["kube-audit", "kube-apiserver", "kube-controller-manager", "kube-scheduler"])
    content {
      category = enabled_log.value
    }
  }

  depends_on = [azapi_update_resource.workspace_transform]
}
