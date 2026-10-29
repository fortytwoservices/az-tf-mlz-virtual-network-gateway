# Reads a local network gateway straight from Azure, to check what the module sent reached it.
terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}

variable "resource_id" {
  type = string
}

data "azapi_resource" "this" {
  type                   = "Microsoft.Network/localNetworkGateways@2025-07-01"
  resource_id            = var.resource_id
  response_export_values = ["properties"]
}

output "properties" {
  value = data.azapi_resource.this.output.properties
}
