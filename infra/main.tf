provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  # ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID, ARM_CLIENT_SECRET
  # are set as Environment Variables in the HCP Terraform workspace.
  # The secret is stored only in HCP TF's encrypted variable store — never in code.
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

# ─── Constrained User Access Administrator for the service principal ────────
#
# Why this exists:
#   Terraform (running as the SP) needs to create azurerm_role_assignment.aci_acr_pull.
#   Creating role assignments requires Microsoft.Authorization/roleAssignments/write.
#   Granting full User Access Administrator would let the SP assign ANY role to
#   anything. The ABAC condition below restricts it to AcrPull only — write and
#   delete are both scoped to the AcrPull role definition GUID.
#
# AcrPull GUID 7f951dda-4ed3-4680-a7ca-43fe172d538d is a built-in Azure role
# with the same ID across all tenants and subscriptions.
#
# Why it cannot be created by Terraform:
#   The SP's own ABAC condition only permits AcrPull assignments. It does not
#   allow granting User Access Administrator (that would be circular/self-escalation).
#   This resource must be created once by the subscription owner, then imported.
#
# First-time setup (run as subscription owner — see docs/getting-started.md):
#   az role assignment create \
#     --assignee-object-id <sp-object-id> \
#     --assignee-principal-type ServicePrincipal \
#     --role "User Access Administrator" \
#     --scope /subscriptions/<subscription-id> \
#     --condition "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {7f951dda-4ed3-4680-a7ca-43fe172d538d})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {7f951dda-4ed3-4680-a7ca-43fe172d538d}))" \
#     --condition-version "2.0"
#
# Import into Terraform state after manual creation:
#   cd infra
#   terraform login          # authenticates Terraform CLI to HCP TF
#   terraform init           # connects to remote state
#   terraform import azurerm_role_assignment.sp_uaa \
#     /subscriptions/<subscription-id>/providers/Microsoft.Authorization/roleAssignments/<assignment-id>
#
# Finding the assignment ID:
#   az role assignment list --assignee <sp-object-id> --role "User Access Administrator" \
#     --query "[0].id" -o tsv
#
# prevent_destroy explanation:
#   Even without this flag, terraform destroy would fail with 403 Forbidden
#   because the SP cannot delete a non-AcrPull assignment. This flag makes the
#   failure explicit at PLAN time with a clear error instead of at apply with a
#   cryptic 403. Before running terraform destroy, run:
#     terraform state rm azurerm_role_assignment.sp_uaa
resource "azurerm_role_assignment" "sp_uaa" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "User Access Administrator"
  principal_id         = var.sp_object_id
  condition_version    = "2.0"
  condition            = "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {7f951dda-4ed3-4680-a7ca-43fe172d538d})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {7f951dda-4ed3-4680-a7ca-43fe172d538d}))"

  lifecycle {
    # Prevents accidental removal — see comment above.
    # Run `terraform state rm azurerm_role_assignment.sp_uaa` before terraform destroy.
    prevent_destroy = true
  }
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
