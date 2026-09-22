locals {
  name_prefix         = "${var.project}-${var.environment}"
  resource_group_name = "rg-${local.name_prefix}"
  cluster_name        = "aks-${local.name_prefix}"
  node_resource_group = "rg-${local.cluster_name}-nodes"
  harbor_fqdn         = "${var.harbor_subdomain}.${var.dns_zone_name}"

  tags = merge(var.tags, {
    environment = var.environment
  })
}

data "azurerm_client_config" "current" {}

data "azurerm_dns_zone" "this" {
  name                = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group
}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
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

resource "azurerm_monitor_workspace" "this" {
  name                = "amw-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

resource "azurerm_monitor_data_collection_endpoint" "prometheus" {
  name                = "MSProm-${local.cluster_name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  kind                = "Linux"
  tags                = local.tags
}

resource "azurerm_monitor_data_collection_rule" "prometheus" {
  name                        = "MSProm-${local.cluster_name}"
  resource_group_name         = azurerm_resource_group.this.name
  location                    = azurerm_resource_group.this.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prometheus.id
  kind                        = "Linux"
  tags                        = local.tags

  data_sources {
    prometheus_forwarder {
      name    = "PrometheusDataSource"
      streams = ["Microsoft-PrometheusMetrics"]
    }
  }

  destinations {
    monitor_account {
      name               = "MonitoringAccount"
      monitor_account_id = azurerm_monitor_workspace.this.id
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount"]
  }
}

resource "azurerm_monitor_data_collection_rule_association" "prometheus" {
  name                    = "MSProm-${local.cluster_name}"
  target_resource_id      = module.aks.cluster_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.prometheus.id
}

resource "azurerm_dashboard_grafana" "this" {
  name                  = "grafana-${local.name_prefix}"
  resource_group_name   = azurerm_resource_group.this.name
  location              = azurerm_resource_group.this.location
  grafana_major_version = 12
  tags                  = local.tags

  identity {
    type = "SystemAssigned"
  }

  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.this.id
  }
}

resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  scope                = azurerm_monitor_workspace.this.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.this.identity[0].principal_id
}

module "network" {
  source = "./modules/network"

  project             = var.project
  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

module "aks" {
  source = "./modules/aks"

  cluster_name               = local.cluster_name
  resource_group_name        = azurerm_resource_group.this.name
  location                   = var.location
  node_resource_group_name   = local.node_resource_group
  vnet_id                    = module.network.vnet_id
  vnet_subnet_id             = module.network.aks_subnet_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  kubernetes_version         = var.kubernetes_version
  user_object_id             = var.user_object_id
  tags                       = local.tags
}

module "bastion" {
  source = "./modules/bastion"

  project                       = var.project
  environment                   = var.environment
  location                      = var.location
  resource_group_name           = azurerm_resource_group.this.name
  bastion_subnet_id             = module.network.bastion_subnet_id
  bastion_subnet_address_prefix = module.network.bastion_subnet_address_prefix
  jumpbox_subnet_id             = module.network.jumpbox_subnet_id
  jumpbox_vm_size               = var.jumpbox_vm_size
  jumpbox_admin_username        = var.jumpbox_admin_username
  jumpbox_ssh_public_key        = var.jumpbox_ssh_public_key
  jumpbox_admin_password        = var.jumpbox_admin_password
  tags                          = local.tags
}

module "identity" {
  source = "./modules/identity"

  project              = var.project
  environment          = var.environment
  location             = var.location
  resource_group_name  = azurerm_resource_group.this.name
  oidc_issuer_url      = module.aks.oidc_issuer_url
  dns_zone_resource_id = data.azurerm_dns_zone.this.id
  harbor_fqdn          = local.harbor_fqdn
  user_object_id       = var.user_object_id
  tags                 = local.tags

  enable_oidc_auth                = var.enable_oidc_auth
  harbor_oidc_app_display_name    = var.harbor_oidc_app_display_name
  harbor_admin_group_name         = var.harbor_admin_group_name
  harbor_projectadmin_group_name  = var.harbor_projectadmin_group_name
  harbor_maintainer_group_name    = var.harbor_maintainer_group_name
  harbor_developer_group_name     = var.harbor_developer_group_name
  harbor_guest_group_name         = var.harbor_guest_group_name
  harbor_limited_guest_group_name = var.harbor_limited_guest_group_name
  harbor_admin_group_member_upns  = var.harbor_admin_group_member_upns
}

module "postgres" {
  source = "./modules/postgres"

  project             = var.project
  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = module.network.postgres_subnet_id
  private_dns_zone_id = module.network.postgres_private_dns_zone_id
  tenant_id           = data.azurerm_client_config.current.tenant_id
  user_object_id      = var.user_object_id
  tags                = local.tags
}

module "redis" {
  source = "./modules/redis"

  project               = var.project
  environment           = var.environment
  location              = var.location
  resource_group_name   = azurerm_resource_group.this.name
  privatelink_subnet_id = module.network.privatelink_subnet_id
  private_dns_zone_id   = module.network.redis_private_dns_zone_id
  tags                  = local.tags
}

resource "random_password" "harbor_admin" {
  length  = 20
  special = true
}

# AES key consumed by Harbor core - must be exactly 16 characters.
resource "random_password" "harbor_secret_key" {
  length  = 16
  special = false
}

resource "random_password" "harbor_core_secret" {
  length  = 32
  special = false
}

resource "random_password" "harbor_core_xsrf_key" {
  length  = 32
  special = false
}

resource "random_password" "harbor_jobservice_secret" {
  length  = 32
  special = false
}

resource "random_password" "harbor_registry_http_secret" {
  length  = 32
  special = false
}

resource "random_password" "harbor_registry_passwd" {
  length  = 32
  special = false
}

locals {
  harbor_registry_htpasswd = "harbor_registry_user:${bcrypt(random_password.harbor_registry_passwd.result)}"
}

module "keyvault" {
  source = "./modules/keyvault"

  project                   = var.project
  environment               = var.environment
  location                  = var.location
  resource_group_name       = azurerm_resource_group.this.name
  tenant_id                 = data.azurerm_client_config.current.tenant_id
  privatelink_subnet_id     = module.network.privatelink_subnet_id
  private_dns_zone_id       = module.network.vault_private_dns_zone_id
  kv_csi_identity_object_id = module.aks.key_vault_identity_object_id
  user_object_id            = var.user_object_id
  tags                      = local.tags

  harbor_admin_password       = random_password.harbor_admin.result
  postgres_password           = module.postgres.postgres_password
  redis_password              = module.redis.redis_password
  harbor_secret_key           = random_password.harbor_secret_key.result
  harbor_core_secret          = random_password.harbor_core_secret.result
  harbor_core_xsrf_key        = random_password.harbor_core_xsrf_key.result
  harbor_jobservice_secret    = random_password.harbor_jobservice_secret.result
  harbor_registry_http_secret = random_password.harbor_registry_http_secret.result
  harbor_registry_passwd      = random_password.harbor_registry_passwd.result
  harbor_registry_htpasswd    = local.harbor_registry_htpasswd
}
