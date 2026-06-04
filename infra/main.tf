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

# Wait for the Docker image to exist in ACR before creating the container group.
# This prevents a 400 InaccessibleImage error on fresh deployments where Terraform
# and GitHub Actions build/push run in parallel.
#
# The provisioner uses the ARM_* workspace env vars (client credentials) to obtain
# an ACR-scoped OAuth token, then polls the Docker v2 registry API for the image.
# Timeout: 30 attempts × 10 seconds = 5 minutes.
#
# In the typical flow the image is already present by the time the HCP TF apply
# is approved, so the wait exits in seconds.
resource "null_resource" "wait_for_image" {
  count = var.create_aci ? 1 : 0

  # Re-run this check whenever the target image changes (new SHA or tag)
  triggers = {
    image = "${azurerm_container_registry.acr.login_server}/${var.project}:${var.image_tag}"
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      ACR="${azurerm_container_registry.acr.login_server}"
      REPO="${var.project}"
      TAG="${var.image_tag}"

      echo "Waiting for $REPO:$TAG in $ACR ..."

      # Step 1: get ARM management token using the client credentials from workspace env vars
      MGMT_TOKEN=$(curl -sf -X POST \
        "https://login.microsoftonline.com/$ARM_TENANT_ID/oauth2/v2.0/token" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "client_id=$ARM_CLIENT_ID" \
        --data-urlencode "client_secret=$ARM_CLIENT_SECRET" \
        --data-urlencode "scope=https://management.azure.com/.default" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

      # Step 2: exchange ARM token for an ACR-scoped refresh token
      ACR_REFRESH=$(curl -sf \
        "https://$ACR/oauth2/exchange" \
        --data-urlencode "grant_type=access_token" \
        --data-urlencode "service=$ACR" \
        --data-urlencode "access_token=$MGMT_TOKEN" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['refresh_token'])")

      # Step 3: exchange refresh token for a scoped ACR access token (pull-only)
      ACR_TOKEN=$(curl -sf \
        "https://$ACR/oauth2/token" \
        --data-urlencode "grant_type=refresh_token" \
        --data-urlencode "service=$ACR" \
        --data-urlencode "scope=repository:$REPO:pull" \
        --data-urlencode "refresh_token=$ACR_REFRESH" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

      # Step 4: poll the Docker v2 manifest endpoint until the tag is found
      for i in $(seq 1 30); do
        HTTP=$(curl -s -o /dev/null -w "%%{http_code}" \
          -H "Authorization: Bearer $ACR_TOKEN" \
          "https://$ACR/v2/$REPO/manifests/$TAG")

        if [ "$HTTP" = "200" ]; then
          echo "Image $REPO:$TAG found after $((i * 10))s."
          exit 0
        fi

        echo "Attempt $i/30: not yet available (HTTP $HTTP) — waiting 10s..."
        sleep 10
      done

      echo "ERROR: $REPO:$TAG not found in $ACR after 5 minutes."
      echo "Ensure the GitHub Actions deploy pipeline pushed the image successfully."
      exit 1
    EOT
  }

  depends_on = [
    azurerm_container_registry.acr,
    azurerm_role_assignment.aci_acr_pull,
  ]
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

  depends_on = [
    azurerm_role_assignment.aci_acr_pull,
    null_resource.wait_for_image,
  ]
}
