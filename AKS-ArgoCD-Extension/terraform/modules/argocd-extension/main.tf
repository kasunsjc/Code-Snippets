# AKS Argo CD extension (Microsoft.ArgoCD).
#
# Reference:
#   https://learn.microsoft.com/azure/azure-arc/kubernetes/tutorial-use-gitops-argocd
#   https://blog.aks.azure.com/2026/04/22/argocd-extension-with-microsoft-entra

resource "azapi_resource" "argocd" {
  type      = "Microsoft.KubernetesConfiguration/extensions@2023-05-01"
  name      = "argocd"
  parent_id = var.cluster_id

  body = {
    properties = {
      extensionType           = "Microsoft.ArgoCD"
      autoUpgradeMinorVersion = true
      releaseTrain            = "stable"

      scope = {
        cluster = {
          releaseNamespace = var.argocd_namespace
        }
      }

      configurationSettings = {
        "namespaceInstall" = "false"

        # Microsoft Entra ID SSO
        "sso.provider"        = "entra"
        "sso.entra.tenantId"  = var.tenant_id
        "sso.entra.clientId"  = var.client_id
        "sso.entra.issuerUrl" = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
        "sso.redirectUrl"     = "https://${var.argocd_hostname}/auth/callback"

        # RBAC
        "rbac.policy.default" = "role:readonly"
        "rbac.policy.csv"     = "g, ${var.admin_group_object_id}, role:admin"
        "rbac.scopes"         = "[groups]"

        # Ingress via AKS managed NGINX (App Routing)
        "server.ingress.enabled"          = "true"
        "server.ingress.ingressClassName" = "webapprouting.kubernetes.azure.com"
        "server.ingress.hostname"         = var.argocd_hostname
        "server.ingress.tls"              = "true"
      }

      configurationProtectedSettings = {
        "sso.entra.clientSecret" = var.client_secret
      }
    }
  }

  schema_validation_enabled = false
  response_export_values    = ["properties.provisioningState", "properties.statuses"]

  lifecycle {
    ignore_changes = [body]
  }
}
