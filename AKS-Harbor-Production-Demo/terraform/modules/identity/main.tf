resource "azurerm_user_assigned_identity" "cert_manager" {
  name                = "id-cert-manager-${var.project}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "cert_manager" {
  name                = "cert-manager"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.cert_manager.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:cert-manager:cert-manager"
}

resource "azurerm_role_assignment" "dns_zone_contributor" {
  scope                = var.dns_zone_resource_id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.cert_manager.principal_id
}

# --- Microsoft Entra ID OIDC SSO for Harbor -----------------------------------
# Harbor authenticates users via this app's client secret; group membership
# (ApplicationGroup claim) onboards users, and the harbor-admins group maps to
# Harbor's global system admin via oidc_admin_group (matched by object ID -
# Entra emits group object IDs in the token, not display names).

data "azurerm_client_config" "current" {}

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
    redirect_uris = ["https://${var.harbor_fqdn}/c/oidc/callback"]
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
locals {
  harbor_oidc_groups = var.enable_oidc_auth ? {
    admins         = azuread_group.harbor_admins[0].object_id
    projectadmins  = azuread_group.harbor_projectadmins[0].object_id
    maintainers    = azuread_group.harbor_maintainers[0].object_id
    developers     = azuread_group.harbor_developers[0].object_id
    guests         = azuread_group.harbor_guests[0].object_id
    limited_guests = azuread_group.harbor_limited_guests[0].object_id
  } : {}
}

resource "azuread_app_role_assignment" "harbor_groups" {
  for_each = local.harbor_oidc_groups

  app_role_id         = "00000000-0000-0000-0000-000000000000" # default access role
  principal_object_id = each.value
  resource_object_id  = azuread_service_principal.harbor[0].object_id
}
