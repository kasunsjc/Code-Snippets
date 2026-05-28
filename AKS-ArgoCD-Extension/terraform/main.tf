locals {
  name_prefix         = "${var.project}-${var.environment}"
  resource_group_name = "rg-${local.name_prefix}"
  node_resource_group = "rg-${local.name_prefix}-nodes"
  cluster_name        = "aks-${local.name_prefix}"
  key_vault_name      = substr(replace("kv-${local.name_prefix}-${random_string.suffix.result}", "_", "-"), 0, 24)
  log_workspace_name  = "log-${local.name_prefix}"
  argocd_namespace    = "argocd"
  certificate_name    = "argocd-ingress-tls"

  tags = {
    project     = var.project
    environment = var.environment
    demo        = "aks-argocd-extension"
    managed_by  = "terraform"
  }
}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
  numeric = true
}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

# --- Existing DNS zone (referenced for App Routing zone attachment) -----------

data "azurerm_dns_zone" "this" {
  name                = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group
}

# --- Observability ------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = local.log_workspace_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# --- AKS cluster --------------------------------------------------------------
# - Workload Identity + OIDC issuer enabled (required by the Argo CD extension
#   for Microsoft Entra federation).
# - Application Routing (managed NGINX) add-on enabled via web_app_routing.
# - Custom node resource group name per repo convention.

resource "azurerm_kubernetes_cluster" "this" {
  name                      = local.cluster_name
  location                  = azurerm_resource_group.this.location
  resource_group_name       = azurerm_resource_group.this.name
  node_resource_group       = local.node_resource_group
  dns_prefix                = local.cluster_name
  kubernetes_version        = var.kubernetes_version
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  azure_policy_enabled      = true
  local_account_disabled    = false
  sku_tier                  = "Standard"
  tags                      = local.tags

  default_node_pool {
    name         = "system"
    vm_size      = var.node_vm_size
    node_count   = var.node_count
    os_disk_type = "Ephemeral"
    os_sku       = "AzureLinux"
    max_pods     = 60
    type         = "VirtualMachineScaleSets"
    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
  }

  # Azure NGINX add-on (Application Routing).
  # dns_zone_ids attaches the existing public DNS zone; managed identity for the
  # add-on automatically gets the DNS Zone Contributor role on the listed zones.
  web_app_routing {
    dns_zone_ids = [data.azurerm_dns_zone.this.id]
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  }
}

# --- Key Vault for ingress TLS certificate ------------------------------------

resource "azurerm_key_vault" "this" {
  name                       = local.key_vault_name
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  tags                       = local.tags
}

# Allow the Terraform principal to import the certificate.
resource "azurerm_role_assignment" "tf_kv_cert_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Allow the App Routing add-on managed identity to read the certificate. The
# add-on uses the cluster's web_app_routing_identity (kubelet-style identity
# created for the add-on) to pull the cert via Secrets Store CSI.
resource "azurerm_role_assignment" "approuting_kv_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.this.web_app_routing[0].web_app_routing_identity[0].object_id
}

resource "azurerm_key_vault_certificate" "ingress" {
  name         = local.certificate_name
  key_vault_id = azurerm_key_vault.this.id

  certificate {
    contents = filebase64(var.certificate_pfx_path)
    password = var.certificate_pfx_password
  }

  depends_on = [azurerm_role_assignment.tf_kv_cert_officer]
}

# --- Attach Key Vault to the App Routing add-on -------------------------------
# The azurerm provider does not yet expose this directly; use the Azure CLI to
# call `az aks approuting update --enable-kv --attach-kv`. Idempotent: running
# again with the same KV is a no-op.

resource "null_resource" "approuting_attach_kv" {
  triggers = {
    cluster_id   = azurerm_kubernetes_cluster.this.id
    key_vault_id = azurerm_key_vault.this.id
  }

  provisioner "local-exec" {
    command     = <<-EOT
      az aks approuting update \
        --resource-group ${azurerm_resource_group.this.name} \
        --name ${azurerm_kubernetes_cluster.this.name} \
        --enable-kv \
        --attach-kv ${azurerm_key_vault.this.id}
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    azurerm_role_assignment.approuting_kv_secrets_user,
    azurerm_key_vault_certificate.ingress,
  ]
}
