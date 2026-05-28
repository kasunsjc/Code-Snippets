# Microsoft Entra ID application used as the OIDC IdP for Argo CD SSO.
#
# Argo CD's Dex (bundled with the AKS Argo CD extension) is configured with the
# client id / secret of this app and authenticates users against Entra ID. The
# `groups` optional claim is emitted so the argocd-rbac-cm can map an Entra
# group to the built-in admin role.

resource "azuread_application" "argocd" {
  display_name     = "argocd-${var.project}-${var.environment}"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]

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
      name                  = "groups"
      additional_properties = []
      essential             = false
    }

    access_token {
      name                  = "groups"
      additional_properties = []
      essential             = false
    }
  }

  group_membership_claims = ["SecurityGroup"]

  required_resource_access {
    # Microsoft Graph
    resource_app_id = "00000003-0000-0000-c000-000000000000"

    # User.Read - delegated
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"
      type = "Scope"
    }
    # GroupMember.Read.All - delegated
    resource_access {
      id   = "bc024368-1153-4739-b217-4326f2e966d0"
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "argocd" {
  client_id = azuread_application.argocd.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_password" "argocd" {
  application_id = azuread_application.argocd.id
  display_name   = "argocd-sso"
  end_date       = "2099-12-31T23:59:59Z"
}
