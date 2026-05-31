# AKS Argo CD extension (Microsoft.ArgoCD).
#
# Reference:
#   https://learn.microsoft.com/azure/azure-arc/kubernetes/tutorial-use-gitops-argocd
#   https://blog.aks.azure.com/2026/04/22/argocd-extension-with-microsoft-entra

locals {
  # OIDC config YAML passed to configs.cm — uses workload identity so no
  # client secret is required. argocd-server exchanges its projected K8s SA
  # token for an Entra ID token via OIDC federation.
  oidc_config = yamlencode({
    name     = "Microsoft Entra ID"
    issuer   = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
    clientID = var.client_id
    azure = {
      useWorkloadIdentity = true
    }
    requestedIDTokenClaims = {
      groups = {
        essential = true
      }
    }
    requestedScopes = ["openid", "profile", "email"]
  })
}

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

        # Disable HA — single replica per component
        "controller.replicas" = "1"
        "server.replicas"     = "1"
        "repoServer.replicas" = "1"

        # Workload identity — the extension labels pods and annotates service
        # accounts automatically once these three keys are set.
        "azure.workloadIdentity.enabled"          = "true"
        "azure.workloadIdentity.clientId"         = var.workload_identity_client_id
        "azure.workloadIdentity.entraSSOClientId" = var.client_id

        # OIDC SSO via workload identity (no client secret required)
        "configs.cm.url"             = "https://${var.argocd_hostname}/"
        "configs.cm.oidc\\.config"   = local.oidc_config
        "configs.cm.admin\\.enabled" = "false"

        # RBAC
        "configs.rbac.policy\\.default" = "role:readonly"
        "configs.rbac.policy\\.csv"     = "g, ${var.admin_group_object_id}, role:admin"
        "configs.rbac.scopes"           = "[groups]"

        # Run argocd-server in insecure mode (plain HTTP) so TLS terminates at
        # the managed NGINX ingress. Without this the server keeps serving
        # HTTPS and 307-redirects every request back to HTTPS, which produces
        # an infinite "too many redirects" loop behind the TLS-terminating
        # ingress. Sets server.insecure=true in argocd-cmd-params-cm.
        "configs.params.server\\.insecure" = "true"

        # Ingress via AKS managed NGINX (App Routing)
        "server.ingress.enabled"          = "true"
        "server.ingress.ingressClassName" = "webapprouting.kubernetes.azure.com"
        "server.ingress.hostname"         = var.argocd_hostname
        "server.ingress.tls"              = "true"
      }
    }
  }

  schema_validation_enabled = false
  response_export_values    = ["properties.provisioningState", "properties.statuses"]

  timeouts {
    create = "60m"
    update = "60m"
    delete = "30m"
  }

  lifecycle {
    ignore_changes = [body]
  }
}
