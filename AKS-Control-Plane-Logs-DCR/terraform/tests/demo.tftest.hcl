mock_provider "azurerm" {
  mock_resource "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dcrlogs-demo"
    }
  }

  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dcrlogs-demo/providers/Microsoft.OperationalInsights/workspaces/log-dcrlogs-demo"
    }
  }

  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dcrlogs-demo/providers/Microsoft.ContainerService/managedClusters/aks-dcrlogs-demo"
    }
  }

  mock_resource "azurerm_monitor_data_collection_rule" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dcrlogs-demo/providers/Microsoft.Insights/dataCollectionRules/dcr-dcrlogs-demo"
    }
  }
}

mock_provider "azapi" {}

run "demo_contract" {
  command = apply
  variables {
    api_server_authorized_ip_ranges = ["203.0.113.10/32"]
  }

  assert {
    condition = length(azapi_resource_action.table) == 4 && alltrue([
      for table in azapi_resource_action.table :
      table.method == "PUT" && table.when == "apply"
    ])
    error_message = "Prepare built-in tables without attempting unsupported table DELETEs on destroy."
  }

  assert {
    condition     = azurerm_monitor_data_collection_rule.transform.kind == "WorkspaceTransforms"
    error_message = "Diagnostic ingestion requires a workspace transformation DCR."
  }

  assert {
    condition = toset(flatten([
      for flow in azurerm_monitor_data_collection_rule.transform.data_flow : flow.streams
    ])) == toset(["Microsoft-Table-AKSAudit", "Microsoft-Table-AKSControlPlane"])
    error_message = "Both built-in table streams must be transformed."
  }

  assert {
    condition = alltrue([
      for flow in azurerm_monitor_data_collection_rule.transform.data_flow :
      flow.transform_kql == trimspace(file("${path.module}/../transforms/${trimprefix(one(flow.streams), "Microsoft-Table-")}.kql"))
    ])
    error_message = "DCR policies must come directly from the reviewed KQL files."
  }

  assert {
    condition = alltrue([
      for setting in azurerm_monitor_diagnostic_setting.aks :
      setting.log_analytics_destination_type == "Dedicated" &&
      toset([for log in setting.enabled_log : log.category]) ==
      toset(["kube-audit", "kube-apiserver", "kube-controller-manager", "kube-scheduler"])
    ])
    error_message = "Baseline and transformed workspaces must receive identical resource-specific categories."
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.this.node_resource_group == "rg-dcrlogs-demo-nodes" &&
      azurerm_kubernetes_cluster.this.api_server_access_profile[0].authorized_ip_ranges == toset(["203.0.113.10/32"])
    )
    error_message = "AKS must retain an explicit node group and a restricted API endpoint."
  }

  assert {
    condition = (
      azapi_update_resource.workspace_transform.body.properties.defaultDataCollectionRuleResourceId ==
      azurerm_monitor_data_collection_rule.transform.id &&
      azapi_resource_action.unlink_workspace_transform.when == "destroy" &&
      azapi_resource_action.unlink_workspace_transform.body.properties.defaultDataCollectionRuleResourceId == ""
    )
    error_message = "The workspace DCR must be linked on deploy and unlinked on destroy."
  }
}

run "default_ip_ranges_optional" {
  command = plan

  assert {
    condition     = length(var.api_server_authorized_ip_ranges) == 0 && length(azurerm_kubernetes_cluster.this.api_server_access_profile[0].authorized_ip_ranges) == 0
    error_message = "Omitting authorized IP ranges must disable IP restrictions."
  }
}

run "empty_ip_ranges_optional" {
  command = plan
  variables {
    api_server_authorized_ip_ranges = []
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.this.api_server_access_profile[0].authorized_ip_ranges) == 0
    error_message = "An explicit empty list must disable IP restrictions."
  }
}

run "reject_open_api" {
  command = plan
  variables {
    api_server_authorized_ip_ranges = ["0.0.0.0/0"]
  }
  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "reject_invalid_cidr" {
  command = plan
  variables {
    api_server_authorized_ip_ranges = ["not-a-cidr"]
  }
  expect_failures = [var.api_server_authorized_ip_ranges]
}
