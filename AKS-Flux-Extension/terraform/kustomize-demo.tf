# Preserve the first article's configuration name and Terraform resource address.
resource "azurerm_kubernetes_flux_configuration" "this" {
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
}
