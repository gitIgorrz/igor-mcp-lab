output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}

output "aci_identity_client_id" {
  value = azurerm_user_assigned_identity.aci_identity.client_id
}

output "mcp_fqdn" {
  value = var.create_aci ? azurerm_container_group.mcp[0].fqdn : null
}

output "mcp_health_url" {
  value = var.create_aci ? "http://${azurerm_container_group.mcp[0].fqdn}:${var.mcp_server_port}/health" : null
}

output "mcp_endpoint_url" {
  value = var.create_aci ? "http://${azurerm_container_group.mcp[0].fqdn}:${var.mcp_server_port}/mcp" : null
}
