terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.20"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      # Soft-deleted Key Vaults, and slow-to-delete resources like Redis
      # Enterprise, can still appear "in" the RG for a bit after Terraform
      # issues their delete - let RG deletion cascade instead of blocking on it.
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azuread" {}
