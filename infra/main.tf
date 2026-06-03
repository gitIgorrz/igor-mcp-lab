provider "azurerm" {
  features {}
  use_oidc        = true
  oidc_token      = var.tfc_workload_identity_token_azurerm
  subscription_id = var.subscription_id
  # HCP Terraform automatically populates tfc_workload_identity_token_azurerm
  # with a short-lived OIDC JWT (audience: api://AzureADTokenExchange) when
  # TFC_WORKLOAD_IDENTITY_AUDIENCE_AZURERM is set in the workspace. ARM_CLIENT_ID,
  # ARM_TENANT_ID, ARM_SUBSCRIPTION_ID must be set as workspace env vars.
  # No client secrets stored anywhere.
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  name_suffix = random_string.suffix.result
  acr_name    = "${var.project}${local.name_suffix}"
  tags = {
    project     = var.project
    managed-by  = "terraform"
    environment = "lab"
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.project}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_container_registry" "acr" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "aci_identity" {
  name                = "id-${var.project}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = local.tags
}

data "azurerm_role_definition" "acr_pull" {
  name = "AcrPull"
}

resource "azurerm_role_assignment" "aci_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.aci_identity.principal_id
}

resource "azurerm_container_group" "mcp" {
  count               = var.create_aci ? 1 : 0
  name                = "aci-${var.project}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  ip_address_type     = "Public"
  dns_name_label      = "mcp-${var.project}"
  os_type             = "Linux"
  tags                = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aci_identity.id]
  }

  image_registry_credential {
    server                    = azurerm_container_registry.acr.login_server
    user_assigned_identity_id = azurerm_user_assigned_identity.aci_identity.id
  }

  container {
    name   = "mcp-server"
    image  = "${azurerm_container_registry.acr.login_server}/${var.project}:${var.image_tag}"
    cpu    = var.aci_cpu
    memory = var.aci_memory_gb

    ports {
      port     = var.mcp_server_port
      protocol = "TCP"
    }

    environment_variables = {
      PORT        = tostring(var.mcp_server_port)
      ENVIRONMENT = "azure"
      IMAGE_TAG   = var.image_tag
      DEPLOYED_AT = var.deployed_at
    }

    liveness_probe {
      http_get {
        path   = "/health"
        port   = var.mcp_server_port
        scheme = "http"
      }
      initial_delay_seconds = 15
      period_seconds        = 20
      failure_threshold     = 3
    }

    readiness_probe {
      http_get {
        path   = "/health"
        port   = var.mcp_server_port
        scheme = "http"
      }
      initial_delay_seconds = 5
      period_seconds        = 10
    }
  }

  depends_on = [azurerm_role_assignment.aci_acr_pull]
}
