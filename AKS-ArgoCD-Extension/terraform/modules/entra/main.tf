# Microsoft Entra ID application used as the OIDC IdP for Argo CD SSO.
#
# Argo CD's built-in OIDC client is configured with the client ID of this app
# and authenticates users against Entra ID via workload identity (no secret).
# The `groups` optional claim is emitted so the argocd-rbac-cm can map an
# Entra group to the built-in admin role.

# --- Data sources for Microsoft Graph ----------------------------------------

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

# --- Argo CD Entra ID application --------------------------------------------

resource "azuread_application" "argocd" {
  display_name     = var.application_display_name
  sign_in_audience = "AzureADMyOrg"
  owners           = [var.owner_object_id]

  # ApplicationGroup — only groups explicitly assigned to this app are included
  # in the token. Combined with azuread_app_role_assignment below, this keeps
  # token size small and avoids leaking unrelated group memberships.
  group_membership_claims = ["ApplicationGroup"]

  web {
    redirect_uris = distinct(concat(
      [
        "https://${var.argocd_hostname}/auth/callback",
        "https://${var.argocd_hostname}/api/dex/callback",
      ],
      var.extra_redirect_uris,
    ))

    implicit_grant {
      id_token_issuance_enabled = true
    }
  }

  optional_claims {
    id_token {
      name      = "groups"
      essential = true
    }
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    # openid, profile, email, User.Read — delegated scopes for OIDC login
    resource_access {
      id   = data.azuread_service_principal.msgraph.oauth2_permission_scope_ids["openid"]
      type = "Scope"
    }
    resource_access {
      id   = data.azuread_service_principal.msgraph.oauth2_permission_scope_ids["profile"]
      type = "Scope"
    }
    resource_access {
      id   = data.azuread_service_principal.msgraph.oauth2_permission_scope_ids["email"]
      type = "Scope"
    }
    resource_access {
      id   = data.azuread_service_principal.msgraph.oauth2_permission_scope_ids["User.Read"]
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "argocd" {
  client_id = azuread_application.argocd.client_id
  owners    = [var.owner_object_id]
}

# Pre-consent Graph permissions so users won't see a consent prompt at login.
resource "azuread_service_principal_delegated_permission_grant" "argocd" {
  service_principal_object_id          = azuread_service_principal.argocd.object_id
  resource_service_principal_object_id = data.azuread_service_principal.msgraph.object_id
  claim_values                         = ["openid", "profile", "email", "User.Read"]
}

# Federated identity credential — lets argocd-server exchange its Kubernetes
# projected service account token for an Entra ID token (workload identity SSO).
resource "azuread_application_federated_identity_credential" "argocd_server" {
  application_id = azuread_application.argocd.id
  display_name   = "argocd-server-wi"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = var.oidc_issuer_url
  subject        = "system:serviceaccount:argocd:argocd-server"
}

# --- Argo CD admin group & membership ----------------------------------------

resource "azuread_group" "argocd_admins" {
  display_name     = var.admin_group_name
  security_enabled = true
  owners           = [var.owner_object_id]
  description      = "Members of this group are granted the Argo CD admin role via SSO."
}

resource "azuread_group_member" "current_user" {
  group_object_id  = azuread_group.argocd_admins.object_id
  member_object_id = var.owner_object_id
}

# Assign the admin group to the app's default role so group membership appears
# in the token when group_membership_claims = ["ApplicationGroup"].
resource "azuread_app_role_assignment" "argocd_admins" {
  app_role_id         = "00000000-0000-0000-0000-000000000000" # default access role
  principal_object_id = azuread_group.argocd_admins.object_id
  resource_object_id  = azuread_service_principal.argocd.object_id
}
