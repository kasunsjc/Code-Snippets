locals {
  name_prefix         = "${var.project}-${var.environment}"
  resource_group_name = "rg-${local.name_prefix}"
  cluster_name        = "aks-${local.name_prefix}"
  node_resource_group = "rg-${local.cluster_name}-nodes"
  log_workspace_name  = "log-${local.name_prefix}"
  monitor_ws_name     = "amw-${local.name_prefix}"
  grafana_name        = "grafana-${local.name_prefix}"
  harbor_fqdn         = "${var.harbor_subdomain}.${var.dns_zone_name}"

  tags = merge(var.tags, {
    environment = var.environment
  })
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

# --- Existing DNS zone (not created here; must already be delegated) ---------

data "azurerm_dns_zone" "this" {
  name                = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group
}

# --- Observability: Container Insights (audit-log blog) -----------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = local.log_workspace_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# --- Observability: Managed Prometheus + Grafana (metrics blog) --------------

resource "azurerm_monitor_workspace" "this" {
  name                = local.monitor_ws_name
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
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.prometheus.id
}

resource "azurerm_dashboard_grafana" "this" {
  name                  = local.grafana_name
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

resource "azurerm_role_assignment" "grafana_admin_user" {
  count                = var.user_object_id == "" ? 0 : 1
  scope                = azurerm_dashboard_grafana.this.id
  role_definition_name = "Grafana Admin"
  principal_id         = var.user_object_id
}

# --- Workload identity for cert-manager's Azure DNS DNS-01 solver -------------

resource "azurerm_user_assigned_identity" "cert_manager" {
  name                = "id-cert-manager-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "cert_manager" {
  name                = "cert-manager"
  resource_group_name = azurerm_resource_group.this.name
  parent_id           = azurerm_user_assigned_identity.cert_manager.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject             = "system:serviceaccount:cert-manager:cert-manager"
}

resource "azurerm_role_assignment" "cert_manager_dns_zone_contributor" {
  scope                = data.azurerm_dns_zone.this.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.cert_manager.principal_id
}

# --- AKS cluster ---------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "this" {
  name                = local.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = local.cluster_name
  kubernetes_version  = var.kubernetes_version
  node_resource_group = local.node_resource_group
  tags                = local.tags

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name                 = "system"
    vm_size              = var.node_vm_size
    node_count           = var.node_count
    auto_scaling_enabled = true
    min_count            = var.node_min_count
    max_count            = var.node_max_count
    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  }

  monitor_metrics {}

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count
    ]
  }
}

# --- Harbor admin password (generated, never committed) -----------------------

resource "random_password" "harbor_admin" {
  length  = 20
  special = true
}

# --- Microsoft Entra ID OIDC SSO for Harbor -----------------------------------
# Harbor authenticates users via this app's client secret; group membership
# (ApplicationGroup claim) onboards users, and the harbor-admins group maps to
# Harbor's global system admin via oidc_admin_group (matched by object ID -
# Entra emits group object IDs in the token, not display names).

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  count = var.enable_oidc_auth ? 1 : 0

  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

resource "azuread_application" "harbor" {
  count = var.enable_oidc_auth ? 1 : 0

  display_name     = var.harbor_oidc_app_display_name
  sign_in_audience = "AzureADMyOrg"
  owners           = var.user_object_id == "" ? null : [var.user_object_id]

  # ApplicationGroup — only groups explicitly assigned to this app (via the
  # azuread_app_role_assignment resources below) are included in the token.
  group_membership_claims = ["ApplicationGroup"]

  web {
    redirect_uris = ["https://${local.harbor_fqdn}/c/oidc/callback"]
  }

  optional_claims {
    id_token {
      name      = "groups"
      essential = true
    }
  }

  required_resource_access {
    resource_app_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]

    resource_access {
      id   = data.azuread_service_principal.msgraph[0].oauth2_permission_scope_ids["openid"]
      type = "Scope"
    }
    resource_access {
      id   = data.azuread_service_principal.msgraph[0].oauth2_permission_scope_ids["profile"]
      type = "Scope"
    }
    resource_access {
      id   = data.azuread_service_principal.msgraph[0].oauth2_permission_scope_ids["email"]
      type = "Scope"
    }
    resource_access {
      id   = data.azuread_service_principal.msgraph[0].oauth2_permission_scope_ids["offline_access"]
      type = "Scope"
    }
  }
}

resource "azuread_application_password" "harbor" {
  count = var.enable_oidc_auth ? 1 : 0

  application_id = azuread_application.harbor[0].id
  display_name   = "harbor-oidc-secret"
  end_date       = timeadd(timestamp(), "8760h") # 1 year - rotate by tainting/recreating this resource

  lifecycle {
    ignore_changes = [end_date]
  }
}

resource "azuread_service_principal" "harbor" {
  count = var.enable_oidc_auth ? 1 : 0

  client_id = azuread_application.harbor[0].client_id
  owners    = var.user_object_id == "" ? null : [var.user_object_id]
}

# Pre-consent the delegated Graph scopes tenant-wide so users won't see a
# consent prompt at login. user_object_id only affects app/group ownership.
resource "azuread_service_principal_delegated_permission_grant" "harbor" {
  count = var.enable_oidc_auth ? 1 : 0

  service_principal_object_id          = azuread_service_principal.harbor[0].object_id
  resource_service_principal_object_id = data.azuread_service_principal.msgraph[0].object_id
  claim_values                         = ["openid", "profile", "email", "offline_access"]
}

# --- Harbor role groups --------------------------------------------------------

resource "azuread_group" "harbor_admins" {
  count = var.enable_oidc_auth ? 1 : 0

  display_name     = var.harbor_admin_group_name
  security_enabled = true
  owners           = var.user_object_id == "" ? null : [var.user_object_id]
  description      = "Members are onboarded as Harbor system administrators via OIDC SSO."
}

resource "azuread_group" "harbor_projectadmins" {
  count = var.enable_oidc_auth ? 1 : 0

  display_name     = var.harbor_projectadmin_group_name
  security_enabled = true
  owners           = var.user_object_id == "" ? null : [var.user_object_id]
  description      = "Assign to a Harbor project (Members -> Add group, by object ID) to grant the ProjectAdmin role."
}

resource "azuread_group" "harbor_maintainers" {
  count = var.enable_oidc_auth ? 1 : 0

  display_name     = var.harbor_maintainer_group_name
  security_enabled = true
  owners           = var.user_object_id == "" ? null : [var.user_object_id]
  description      = "Assign to a Harbor project (Members -> Add group, by object ID) to grant the Maintainer role."
}

resource "azuread_group" "harbor_developers" {
  count = var.enable_oidc_auth ? 1 : 0

  display_name     = var.harbor_developer_group_name
  security_enabled = true
  owners           = var.user_object_id == "" ? null : [var.user_object_id]
  description      = "Assign to a Harbor project (Members -> Add group, by object ID) to grant the Developer role."
}

resource "azuread_group" "harbor_guests" {
  count = var.enable_oidc_auth ? 1 : 0

  display_name     = var.harbor_guest_group_name
  security_enabled = true
  owners           = var.user_object_id == "" ? null : [var.user_object_id]
  description      = "Assign to a Harbor project (Members -> Add group, by object ID) to grant the read-only Guest role."
}

resource "azuread_group" "harbor_limited_guests" {
  count = var.enable_oidc_auth ? 1 : 0

  display_name     = var.harbor_limited_guest_group_name
  security_enabled = true
  owners           = var.user_object_id == "" ? null : [var.user_object_id]
  description      = "Assign to a Harbor project (Members -> Add group, by object ID) to grant the Limited Guest role (pull only, no logs/member visibility)."
}

data "azuread_user" "harbor_admin_members" {
  for_each = var.enable_oidc_auth ? toset(var.harbor_admin_group_member_upns) : toset([])

  user_principal_name = each.value
}

resource "azuread_group_member" "harbor_admins" {
  for_each = data.azuread_user.harbor_admin_members

  group_object_id  = azuread_group.harbor_admins[0].object_id
  member_object_id = each.value.object_id
}

# Assign each group to the app's default role so group membership appears in
# the token when group_membership_claims = ["ApplicationGroup"].
resource "azuread_app_role_assignment" "harbor_admins" {
  count = var.enable_oidc_auth ? 1 : 0

  app_role_id         = "00000000-0000-0000-0000-000000000000" # default access role
  principal_object_id = azuread_group.harbor_admins[0].object_id
  resource_object_id  = azuread_service_principal.harbor[0].object_id
}

resource "azuread_app_role_assignment" "harbor_projectadmins" {
  count = var.enable_oidc_auth ? 1 : 0

  app_role_id         = "00000000-0000-0000-0000-000000000000"
  principal_object_id = azuread_group.harbor_projectadmins[0].object_id
  resource_object_id  = azuread_service_principal.harbor[0].object_id
}

resource "azuread_app_role_assignment" "harbor_maintainers" {
  count = var.enable_oidc_auth ? 1 : 0

  app_role_id         = "00000000-0000-0000-0000-000000000000"
  principal_object_id = azuread_group.harbor_maintainers[0].object_id
  resource_object_id  = azuread_service_principal.harbor[0].object_id
}

resource "azuread_app_role_assignment" "harbor_developers" {
  count = var.enable_oidc_auth ? 1 : 0

  app_role_id         = "00000000-0000-0000-0000-000000000000"
  principal_object_id = azuread_group.harbor_developers[0].object_id
  resource_object_id  = azuread_service_principal.harbor[0].object_id
}

resource "azuread_app_role_assignment" "harbor_guests" {
  count = var.enable_oidc_auth ? 1 : 0

  app_role_id         = "00000000-0000-0000-0000-000000000000"
  principal_object_id = azuread_group.harbor_guests[0].object_id
  resource_object_id  = azuread_service_principal.harbor[0].object_id
}

resource "azuread_app_role_assignment" "harbor_limited_guests" {
  count = var.enable_oidc_auth ? 1 : 0

  app_role_id         = "00000000-0000-0000-0000-000000000000"
  principal_object_id = azuread_group.harbor_limited_guests[0].object_id
  resource_object_id  = azuread_service_principal.harbor[0].object_id
}
