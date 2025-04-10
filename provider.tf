terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {}

  subscription_id = "815316d6-c838-4ce2-be88-559c7825f41b"
  tenant_id       = "8b87af7d-8647-4dc7-8df4-5f69a2011bb5"
}