variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "bastion_subnet_id" {
  type = string
}

variable "bastion_subnet_address_prefix" {
  type = string
}

variable "jumpbox_subnet_id" {
  type = string
}

variable "jumpbox_vm_size" {
  type    = string
  default = "Standard_B2s"
}

variable "jumpbox_admin_username" {
  type    = string
  default = "azureuser"
}

variable "jumpbox_ssh_public_key" {
  description = "Optional SSH public key for the jumpbox. SSH key auth is more secure than a password - prefer it for anything long-lived."
  type        = string
  default     = ""
}

variable "jumpbox_admin_password" {
  description = "Optional jumpbox admin password. Leave blank to auto-generate one (retrieve it via the jumpbox_admin_password output)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "tags" {
  type = map(string)
}
