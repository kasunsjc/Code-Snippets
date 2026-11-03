# Preserve existing installations when making the foundation demo optional.
moved {
  from = azurerm_kubernetes_flux_configuration.this
  to   = azurerm_kubernetes_flux_configuration.this[0]
}

# Keep the first article's Azure configuration name.
resource "azurerm_kubernetes_flux_configuration" "this" {
  count                             = contains(var.enabled_demos, "kustomize") ? 1 : 0
  name                              = "cluster-config"
  cluster_id                        = azurerm_kubernetes_cluster.this.id
  namespace                         = "cluster-config"
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
    name                       = "apps"
    path                       = var.gitops_path
    garbage_collection_enabled = true
    sync_interval_in_seconds   = 60
    retry_interval_in_seconds  = 30
    timeout_in_seconds         = 300
  }

  depends_on = [azurerm_kubernetes_cluster_extension.flux]

  lifecycle {
    precondition {
      condition     = var.git_repository_url != "" && var.gitops_path != null
      error_message = "The Kustomize demo requires git_repository_url and a non-null gitops_path."
    }
  }
}
