variable "subscription_id" {
  description = "Azure subscription ID — set as workspace variable TF_VAR_subscription_id in HCP Terraform"
  type        = string
  sensitive   = false
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "project" {
  description = "Short project name used in resource naming"
  type        = string
  default     = "igormcplab"
}

variable "image_tag" {
  description = "Docker image tag to deploy — injected per-run from GitHub Actions (git SHA)"
  type        = string
  default     = "latest"
}

variable "create_aci" {
  description = "Set false on bootstrap run (before image exists in ACR), true for all subsequent runs"
  type        = bool
  default     = false
}

variable "mcp_server_port" {
  description = "TCP port the MCP server listens on"
  type        = number
  default     = 3000
}

variable "aci_cpu" {
  type    = number
  default = 0.5
}

variable "aci_memory_gb" {
  type    = number
  default = 0.5
}

variable "deployed_at" {
  description = "ISO-8601 timestamp of this deployment — shown by the server-info tool"
  type        = string
  default     = "unknown"
}

