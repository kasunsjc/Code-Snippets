mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      subscription_id = "00000000-0000-0000-0000-000000000002"
      object_id       = "00000000-0000-0000-0000-000000000003"
    }
  }
}

variables {
  api_server_authorized_ip_ranges = ["198.51.100.20/32"]
}

run "isolated_demo_defaults" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.node_resource_group == "rg-gha-runners-dev-nodes"
    error_message = "AKS must use an explicitly named node resource group."
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this.local_account_disabled && azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control[0].azure_rbac_enabled
    error_message = "AKS must use Entra/Azure RBAC, not local admin accounts."
  }
  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.runners.min_count == 0 && azurerm_kubernetes_cluster_node_pool.runners.max_count == 3 && azurerm_kubernetes_cluster_node_pool.runners.auto_scaling_enabled
    error_message = "Runner nodes must autoscale from zero to the configured cap."
  }
  assert {
    condition     = contains(azurerm_kubernetes_cluster_node_pool.runners.node_taints, "workload=github-actions:NoSchedule")
    error_message = "Runner pool isolation taint must be present."
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].only_critical_addons_enabled
    error_message = "System pool must be tainted for critical components."
  }
}

run "reject_unrestricted_api" {
  command = plan
  variables {
    api_server_authorized_ip_ranges = ["0.0.0.0/0"]
  }
  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "reject_example_api_address" {
  command = plan
  variables {
    api_server_authorized_ip_ranges = ["203.0.113.10/32"]
  }
  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "reject_empty_api_allowlist" {
  command = plan
  variables {
    api_server_authorized_ip_ranges = []
  }
  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "reject_unbounded_node_count" {
  command = plan
  variables {
    runner_node_max_count = 11
  }
  expect_failures = [var.runner_node_max_count]
}

run "reject_old_kubernetes" {
  command = plan
  variables {
    kubernetes_version = "1.28"
  }
  expect_failures = [var.kubernetes_version]
}
