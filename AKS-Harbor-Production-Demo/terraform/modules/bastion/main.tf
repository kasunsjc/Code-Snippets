resource "azurerm_public_ip" "bastion" {
  name                = "pip-bastion-${var.project}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_bastion_host" "this" {
  name                = "bastion-${var.project}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tags                = var.tags

  ip_configuration {
    name                 = "bastion-ipconfig"
    subnet_id            = var.bastion_subnet_id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}

# Only Azure Bastion's own subnet may reach the jumpbox over SSH.
resource "azurerm_network_security_group" "jumpbox" {
  name                = "nsg-jumpbox-${var.project}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowSshFromBastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.bastion_subnet_address_prefix
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "jumpbox" {
  name                = "nic-jumpbox-${var.project}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.jumpbox_subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "jumpbox" {
  network_interface_id      = azurerm_network_interface.jumpbox.id
  network_security_group_id = azurerm_network_security_group.jumpbox.id
}

# cloud-init: az CLI + kubectl + Helm, so an operator can also work interactively.
locals {
  jumpbox_cloud_init = <<-EOT
    #cloud-config
    package_update: true
    packages:
      - ca-certificates
      - curl
      - gnupg
    runcmd:
      - curl -sL https://aka.ms/InstallAzureCLIDeb | bash
      - curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
      - install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
      - curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  EOT
}

resource "azurerm_linux_virtual_machine" "jumpbox" {
  name                  = "vm-jumpbox-${var.project}-${var.environment}"
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.jumpbox_vm_size
  admin_username        = var.jumpbox_admin_username
  network_interface_ids = [azurerm_network_interface.jumpbox.id]
  custom_data           = base64encode(local.jumpbox_cloud_init)
  tags                  = var.tags

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.jumpbox_admin_username
    public_key = var.jumpbox_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
}
