output "bastion_name" {
  value = azurerm_bastion_host.this.name
}

output "jumpbox_vm_id" {
  value = azurerm_linux_virtual_machine.jumpbox.id
}

output "jumpbox_private_ip" {
  value = azurerm_network_interface.jumpbox.private_ip_address
}

output "jumpbox_admin_username" {
  value = var.jumpbox_admin_username
}

output "jumpbox_admin_password" {
  value     = local.jumpbox_admin_password
  sensitive = true
}
