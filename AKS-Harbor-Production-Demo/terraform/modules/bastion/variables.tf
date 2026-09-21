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
  type = string
}

variable "tags" {
  type = map(string)
}
