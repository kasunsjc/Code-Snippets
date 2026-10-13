mock_provider "azurerm" {
  mock_resource "azurerm_kubernetes_automatic_cluster" {
    defaults = {
      id                     = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-gha-runners-dev/providers/Microsoft.ContainerService/managedClusters/aks-gha-runners-dev"
      node_resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/MC_rg-gha-runners-dev_aks-gha-runners-dev_northeurope"
    }
  }
  mock_resource "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-gha-runners-dev"
    }
  }
  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-gha-runners-dev/providers/Microsoft.OperationalInsights/workspaces/log-gha-runners-dev"
    }
  }
  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-gha-runners-dev/providers/Microsoft.Storage/storageAccounts/stghademo"
    }
  }
  mock_data "azurerm_user_assigned_identity" {
    defaults = {
      client_id    = "00000000-0000-0000-0000-000000000006"
      principal_id = "00000000-0000-0000-0000-000000000007"
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

run "isolated_demo_defaults" {
  command = apply

  assert {
    condition     = azurerm_kubernetes_automatic_cluster.this.identity[0].type == "SystemAssigned"
    error_message = "AKS Automatic without hosted_system must use a system-assigned identity."
  }
  assert {
    condition     = length(azurerm_kubernetes_automatic_cluster.this.api_server_access) == 0
    error_message = "Demo default must not restrict the AKS API to authorized IP ranges."
  }
  assert {
    condition     = azurerm_role_assignment.deployer.role_definition_name == "Azure Kubernetes Service RBAC Cluster Admin"
    error_message = "Deployer needs Azure RBAC cluster admin because Automatic disables local accounts."
  }
  assert {
    condition     = output.node_resource_group_name == "MC_rg-gha-runners-dev_aks-gha-runners-dev_northeurope"
    error_message = "Node resource group output must be derived from the AKS-managed group ID."
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
    condition     = azurerm_role_assignment.files_kubelet.role_definition_name == "Storage Account Key Operator Service Role" && azurerm_role_assignment.files_kubelet.principal_id == "00000000-0000-0000-0000-000000000007"
    error_message = "The AKS-managed kubelet identity only needs key retrieval permissions."
  }
}

run "optional_api_allowlist" {
  command = apply
  variables {
    api_server_authorized_ip_ranges = ["198.51.100.20/32"]
  }

  assert {
    condition     = azurerm_kubernetes_automatic_cluster.this.api_server_access[0].authorized_ip_ranges == toset(["198.51.100.20/32"])
    error_message = "AKS API must be restricted to the configured allowlist when provided."
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
