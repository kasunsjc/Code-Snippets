# AKS Argo CD extension (Microsoft.ArgoCD).
#
# Reference:
#   https://learn.microsoft.com/azure/azure-arc/kubernetes/tutorial-use-gitops-argocd
#   https://blog.aks.azure.com/2026/04/22/argocd-extension-with-microsoft-entra
#
# The extension installs Argo CD into the `argocd` namespace and wires its Dex
# bundle to use Microsoft Entra ID as the OIDC IdP. We pass the Entra app's
# client id/secret + tenant id through `configurationSettings` /
# `configurationProtectedSettings`. The settings keys mirror the ones documented
# on the AKS Argo CD extension page; adjust if your extension version uses
# different keys.

resource "azapi_resource" "argocd" {
  type      = "Microsoft.KubernetesConfiguration/extensions@2023-05-01"
  name      = "argocd"
  parent_id = azurerm_kubernetes_cluster.this.id

  body = {
    properties = {
      extensionType           = "Microsoft.ArgoCD"
      autoUpgradeMinorVersion = true
      releaseTrain            = "stable"

      scope = {
        cluster = {
          releaseNamespace = local.argocd_namespace
        }
      }

      configurationSettings = {
        # Where Argo CD is installed
        "namespaceInstall" = "false"

        # Microsoft Entra ID SSO (Dex OIDC connector managed by the extension)
        "sso.provider"        = "entra"
        "sso.entra.tenantId"  = data.azurerm_client_config.current.tenant_id
        "sso.entra.clientId"  = azuread_application.argocd.client_id
        "sso.entra.issuerUrl" = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"
        "sso.redirectUrl"     = "https://${var.argocd_hostname}/auth/callback"

        # RBAC: map the Entra group (by object id) to the built-in admin role,
        # everyone else gets read-only.
        "rbac.policy.default" = "role:readonly"
        "rbac.policy.csv"     = "g, ${var.argocd_admin_group_object_id}, role:admin"
        "rbac.scopes"         = "[groups]"

        # Expose the Argo CD server via the AKS managed NGINX (App Routing)
        # ingress class, with TLS terminated using the Key Vault certificate.
        "server.ingress.enabled"          = "true"
        "server.ingress.ingressClassName" = "webapprouting.kubernetes.azure.com"
        "server.ingress.hostname"         = var.argocd_hostname
        "server.ingress.tls"              = "true"
      }

      configurationProtectedSettings = {
        "sso.entra.clientSecret" = azuread_application_password.argocd.value
      }
    }
  }

  schema_validation_enabled = false
  response_export_values    = ["properties.provisioningState", "properties.statuses"]

  depends_on = [
    null_resource.approuting_attach_kv,
    azuread_service_principal.argocd,
  ]
}
