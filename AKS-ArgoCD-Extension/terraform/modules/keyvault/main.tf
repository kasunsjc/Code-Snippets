resource "azurerm_key_vault" "this" {
  name                       = var.key_vault_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  tags                       = var.tags
}

# Allow the Terraform principal to import the certificate.
resource "azurerm_role_assignment" "tf_kv_cert_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = var.deployer_object_id
}

# Allow the App Routing add-on managed identity to read the certificate.
resource "azurerm_role_assignment" "approuting_kv_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.app_routing_object_id
}

resource "azurerm_key_vault_certificate" "ingress" {
  name         = var.certificate_name
  key_vault_id = azurerm_key_vault.this.id

  certificate {
    contents = var.certificate_pfx_base64
    password = var.certificate_pfx_password
  }

  depends_on = [azurerm_role_assignment.tf_kv_cert_officer]
}

# Attach Key Vault to the App Routing add-on via Azure CLI.
resource "null_resource" "approuting_attach_kv" {
  triggers = {
    cluster_name   = var.aks_cluster_name
    key_vault_id   = azurerm_key_vault.this.id
    resource_group = var.aks_resource_group_name
  }

  provisioner "local-exec" {
    command     = <<-EOT
      az aks approuting update \
        --resource-group ${var.aks_resource_group_name} \
        --name ${var.aks_cluster_name} \
        --enable-kv \
        --attach-kv ${azurerm_key_vault.this.id}
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    azurerm_role_assignment.approuting_kv_secrets_user,
    azurerm_key_vault_certificate.ingress,
  ]
}
