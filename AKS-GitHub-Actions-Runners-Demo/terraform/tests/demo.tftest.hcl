mock_provider "azurerm" {
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-gha-runners-dev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/demo"
      client_id    = "00000000-0000-0000-0000-000000000004"
      principal_id = "00000000-0000-0000-0000-000000000005"
    }
  }
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
  assert {
    condition     = azurerm_storage_account.runners.account_kind == "FileStorage" && azurerm_storage_account.runners.account_tier == "Premium" && azurerm_storage_account.runners.account_replication_type == "LRS"
    error_message = "Demo cache must use Premium_LRS Azure Files."
  }
  assert {
    condition     = azurerm_storage_share.nuget.quota == 100 && azurerm_storage_share.nuget.enabled_protocol == "SMB"
    error_message = "Cache must be a 100 GiB SMB share by default."
  }
  assert {
    condition     = azurerm_role_assignment.files_kubelet.role_definition_name == "Storage Account Key Operator Service Role"
    error_message = "Kubelet only needs key retrieval permissions, not storage administration."
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this.storage_profile[0].file_driver_enabled
    error_message = "Azure Files CSI driver must be enabled."
  }
}

run "reject_undersized_premium_cache" {
  command = plan
  variables {
    cache_share_quota_gib = 99
  }
  expect_failures = [var.cache_share_quota_gib]
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
