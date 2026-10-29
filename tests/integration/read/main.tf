# Reads a gateway and a connection straight from Azure, to check what the module sent reached them.
terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}

variable "connection_id" {
  type = string
}

variable "gateway_id" {
  type = string
}

data "azapi_resource" "gateway" {
  type                   = "Microsoft.Network/virtualNetworkGateways@2025-07-01"
  resource_id            = var.gateway_id
  response_export_values = ["properties"]
}

data "azapi_resource" "connection" {
  type                   = "Microsoft.Network/connections@2025-07-01"
  resource_id            = var.connection_id
  response_export_values = ["properties"]
}

output "connection" {
  value = data.azapi_resource.connection.output.properties
}

output "gateway" {
  value = data.azapi_resource.gateway.output.properties
}
