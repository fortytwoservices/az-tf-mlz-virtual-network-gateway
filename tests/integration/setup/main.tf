# A resource group, a virtual network with GatewaySubnet, a Log Analytics workspace and a self-signed
# point-to-site root certificate for one integration test run.
terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

data "azapi_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azapi_resource" "resource_group" {
  type      = "Microsoft.Resources/resourceGroups@2024-11-01"
  name      = "rg-mlz-vgw-${random_string.suffix.result}"
  parent_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  location  = "swedencentral"
}

resource "azapi_resource" "virtual_network" {
  type      = "Microsoft.Network/virtualNetworks@2024-05-01"
  name      = "vnet-mlz-vgw-${random_string.suffix.result}"
  parent_id = azapi_resource.resource_group.id
  location  = azapi_resource.resource_group.location
  body = {
    properties = {
      addressSpace = { addressPrefixes = ["10.0.0.0/24"] }
    }
  }
}

resource "azapi_resource" "gateway_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = "GatewaySubnet"
  parent_id = azapi_resource.virtual_network.id
  body = {
    properties = { addressPrefixes = ["10.0.0.0/27"] }
  }
}

resource "azapi_resource" "workspace" {
  type      = "Microsoft.OperationalInsights/workspaces@2023-09-01"
  name      = "log-mlz-vgw-${random_string.suffix.result}"
  parent_id = azapi_resource.resource_group.id
  location  = azapi_resource.resource_group.location
  body = {
    properties = {
      retentionInDays = 30
      sku             = { name = "PerGB2018" }
    }
  }
}

resource "tls_private_key" "root" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "root" {
  private_key_pem       = tls_private_key.root.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 24
  allowed_uses          = ["cert_signing", "crl_signing"]

  subject {
    common_name = "mlz-vgw-it-root"
  }
}

output "gateway_subnet_id" {
  value = azapi_resource.gateway_subnet.id
}

output "location" {
  value = azapi_resource.resource_group.location
}

# The certificate's Base64 DER data, as point-to-site takes it: the PEM without its armour lines.
output "root_certificate_data" {
  value = replace(replace(replace(tls_self_signed_cert.root.cert_pem, "-----BEGIN CERTIFICATE-----", ""), "-----END CERTIFICATE-----", ""), "\n", "")
}

output "resource_group_id" {
  value = azapi_resource.resource_group.id
}

output "suffix" {
  value = random_string.suffix.result
}

output "tenant_id" {
  value = data.azapi_client_config.current.tenant_id
}

output "workspace_id" {
  value = azapi_resource.workspace.id
}
