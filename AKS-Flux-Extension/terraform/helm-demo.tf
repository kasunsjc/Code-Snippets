# Reconcile the Helm lesson independently using the shared cluster and extension.
resource "azurerm_kubernetes_flux_configuration" "kubeplay" {
  count                             = contains(var.enabled_demos, "helm") ? 1 : 0
  name                              = "helm-demo-config"
  cluster_id                        = azurerm_kubernetes_cluster.this.id
  namespace                         = "helm-demo-config"
  scope                             = "cluster"
  continuous_reconciliation_enabled = true

  git_repository {
    url                      = var.git_repository_url
    reference_type           = "branch"
    reference_value          = var.git_branch
    sync_interval_in_seconds = 60
    timeout_in_seconds       = 120
  }

  kustomizations {
    name                       = "helm"
    path                       = var.gitops_helm_path
    garbage_collection_enabled = true
    sync_interval_in_seconds   = 60
    retry_interval_in_seconds  = 30
    timeout_in_seconds         = 600
  }

  depends_on = [azurerm_kubernetes_cluster_extension.flux]

  lifecycle {
    precondition {
      condition     = var.git_repository_url != "" && var.gitops_helm_path != null
      error_message = "The Helm demo requires git_repository_url and a non-null gitops_helm_path."
    }
  }
}
