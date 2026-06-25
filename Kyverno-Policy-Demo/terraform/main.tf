data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

locals {
  node_resource_group_name = "rg-${var.cluster_name}-nodes"
}

module "log_analytics" {
  source = "./modules/log_analytics"

  workspace_name      = "${var.cluster_name}-law"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  retention_in_days   = 30
  tags                = var.tags
}

module "aks" {
  source = "./modules/aks"

  cluster_name               = var.cluster_name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this.name
  kubernetes_version         = var.kubernetes_version
  node_count                 = var.node_count
  enable_node_autoscaling    = var.enable_node_autoscaling
  node_min_count             = var.node_min_count
  node_max_count             = var.node_max_count
  node_vm_size               = var.node_vm_size
  node_resource_group_name   = local.node_resource_group_name
  log_analytics_workspace_id = module.log_analytics.workspace_id
  user_object_id             = var.user_object_id
  tags                       = var.tags
}
