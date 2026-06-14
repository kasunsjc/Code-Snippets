# User-assigned managed identity used by the KEDA Prometheus scaler.
resource "azurerm_user_assigned_identity" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Grant the identity permission to read metrics from Azure Managed Prometheus.
resource "azurerm_role_assignment" "monitoring_data_reader" {
  scope                = var.prometheus_workspace_id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

# Federated credential — the AKS managed KEDA add-on's operator pod runs in kube-system
# as 'keda-operator'. KEDA exchanges that SA token for an Azure AD access token to
# authenticate against Azure Managed Prometheus on behalf of the managed identity.
resource "azurerm_federated_identity_credential" "keda_operator" {
  name                = "${var.name}-federated"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.this.id
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:kube-system:keda-operator"
  audience            = ["api://AzureADTokenExchange"]
}
