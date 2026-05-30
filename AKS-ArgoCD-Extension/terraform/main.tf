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

# --- Existing DNS zone --------------------------------------------------------

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

module "aks" {
  source = "./modules/aks"

  cluster_name               = local.cluster_name
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  node_resource_group        = local.node_resource_group
  kubernetes_version         = var.kubernetes_version
  node_count                 = var.node_count
  node_vm_size               = var.node_vm_size
  user_node_pool_name        = var.user_node_pool_name
  user_node_pool_vm_size     = var.user_node_pool_vm_size
  user_node_pool_node_count  = var.user_node_pool_node_count
  dns_zone_id                = data.azurerm_dns_zone.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  tags                       = local.tags
}

# --- Key Vault + TLS certificate ----------------------------------------------

module "keyvault" {
  source = "./modules/keyvault"

  key_vault_name           = local.key_vault_name
  location                 = azurerm_resource_group.this.location
  resource_group_name      = azurerm_resource_group.this.name
  tenant_id                = data.azurerm_client_config.current.tenant_id
  deployer_object_id       = data.azurerm_client_config.current.object_id
  app_routing_object_id    = module.aks.web_app_routing_object_id
  certificate_name         = local.certificate_name
  certificate_pfx_base64   = filebase64(var.certificate_pfx_path)
  certificate_pfx_password = var.certificate_pfx_password
  tags                     = local.tags
}

# --- Microsoft Entra ID application for SSO -----------------------------------

module "entra" {
  source = "./modules/entra"

  application_display_name = "argocd-${var.project}-${var.environment}"
  owner_object_id          = data.azuread_client_config.current.object_id
  argocd_hostname          = var.argocd_hostname
  extra_redirect_uris      = var.extra_redirect_uris
}

# --- DNS Zone Contributor for App Routing (external-dns) ---------------------
# The App Routing managed identity runs external-dns and must be able to
# create/update A records in the Azure DNS zone. Without this role assignment
# the external-dns pod fails to update DNS records for Ingress resources.

resource "azurerm_role_assignment" "approuting_dns_zone_contributor" {
  scope                = data.azurerm_dns_zone.this.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = module.aks.web_app_routing_object_id
}

# --- Workload Identity for Argo CD -------------------------------------------
# A User Assigned Managed Identity with federated credentials allows ArgoCD
# pods (server, application-controller, repo-server) to authenticate to Azure
# services (Key Vault, ACR, etc.) via OIDC without client secrets.

resource "azurerm_user_assigned_identity" "argocd" {
  name                = "id-argocd-${local.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

locals {
  argocd_service_accounts = toset([
    "argocd-server",
    "argocd-application-controller",
    "argocd-repo-server",
  ])
}

resource "azurerm_federated_identity_credential" "argocd" {
  for_each            = local.argocd_service_accounts
  name                = "fic-${replace(each.key, "-", "")}-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  parent_id           = azurerm_user_assigned_identity.argocd.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:${local.argocd_namespace}:${each.key}"
}

# --- Argo CD cluster extension ------------------------------------------------

module "argocd_extension" {
  source = "./modules/argocd-extension"

  cluster_id                 = module.aks.cluster_id
  argocd_namespace           = local.argocd_namespace
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  client_id                  = module.entra.application_client_id
  client_secret              = module.entra.client_secret
  argocd_hostname            = var.argocd_hostname
  admin_group_object_id      = module.entra.admin_group_object_id
  entra_service_principal_id = module.entra.service_principal_id
  keyvault_ready             = module.keyvault.key_vault_id
}
