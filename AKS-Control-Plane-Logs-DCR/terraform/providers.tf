terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.31"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.2"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azapi" {}
