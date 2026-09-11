terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # node_provisioning_profile requires azurerm >= 5.0 (NAP is GA in the AKS API)
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  features {}
}
