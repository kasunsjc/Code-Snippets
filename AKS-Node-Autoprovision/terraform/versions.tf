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
  features {
    resource_group {
      # AKS auto-creates a ContainerInsights solution resource in this RG (outside Terraform
      # state) when the oms_agent add-on is enabled; allow RG deletion despite it.
      prevent_deletion_if_contains_resources = false
    }
  }
}
