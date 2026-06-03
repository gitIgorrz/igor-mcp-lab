terraform {
  required_version = ">= 1.9.0"

  cloud {
    organization = "gitIgorrz"
    workspaces {
      name = "igor-mcp-lab"
    }
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
