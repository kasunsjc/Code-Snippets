mock_provider "azurerm" {}

variables {
  git_repository_url = "https://github.com/example/flux-demos.git"
}

run "setup_only" {
  command = plan
  variables {
    enabled_demos      = []
    git_repository_url = ""
  }
  assert {
    condition     = length(azurerm_kubernetes_flux_configuration.this) == 0 && length(azurerm_kubernetes_flux_configuration.kubeplay) == 0
    error_message = "Setup must provision no Flux configurations and require no Git repository."
  }
}

run "kustomize_only" {
  command = plan
  variables {
    enabled_demos = ["kustomize"]
  }
  assert {
    condition     = length(azurerm_kubernetes_flux_configuration.this) == 1 && length(azurerm_kubernetes_flux_configuration.kubeplay) == 0
    error_message = "Kustomize must provision only cluster-config."
  }
}

run "helm_only" {
  command = plan
  variables {
    enabled_demos = ["helm"]
  }
  assert {
    condition     = length(azurerm_kubernetes_flux_configuration.this) == 0 && length(azurerm_kubernetes_flux_configuration.kubeplay) == 1
    error_message = "Helm must provision only helm-demo-config."
  }
}

run "both_demos" {
  command = plan
  variables {
    enabled_demos = ["helm", "kustomize"]
  }
  assert {
    condition     = length(azurerm_kubernetes_flux_configuration.this) == 1 && length(azurerm_kubernetes_flux_configuration.kubeplay) == 1
    error_message = "Both demos must have independent Flux configurations."
  }
}

run "invalid_demo" {
  command = plan
  variables {
    enabled_demos = ["unknown"]
  }
  expect_failures = [var.enabled_demos]
}

run "missing_repository" {
  command = plan
  variables {
    enabled_demos      = ["helm"]
    git_repository_url = ""
  }
  expect_failures = [azurerm_kubernetes_flux_configuration.kubeplay[0]]
}

run "missing_helm_path" {
  command = plan
  variables {
    enabled_demos    = ["helm"]
    gitops_helm_path = null
  }
  expect_failures = [azurerm_kubernetes_flux_configuration.kubeplay[0]]
}
