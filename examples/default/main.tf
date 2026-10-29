# Subscription from ARM_SUBSCRIPTION_ID or the Azure CLI; credentials from the Azure CLI or OIDC.
provider "azapi" {}

locals {
  location = "swedencentral"
  tags     = { example = "default" }
}

data "azapi_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# The connection's pre-shared key: generated on each run and never stored. The module sends it only when
# `secret_version` changes, so the on-premises side is given the same key out of band (or from a Key
# Vault secret instead).
ephemeral "random_password" "shared_key" {
  length  = 32
  special = false
}

resource "azapi_resource" "resource_group" {
  type      = "Microsoft.Resources/resourceGroups@2024-11-01"
  name      = "rg-mlz-vgw-${random_string.suffix.result}"
  parent_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  location  = local.location

  response_export_values = []
  tags                   = local.tags
}

resource "azapi_resource" "virtual_network" {
  type      = "Microsoft.Network/virtualNetworks@2024-05-01"
  name      = "vnet-mlz-vgw-${random_string.suffix.result}"
  parent_id = azapi_resource.resource_group.id
  location  = local.location
  body = {
    properties = {
      addressSpace = { addressPrefixes = ["10.0.0.0/24"] }
    }
  }

  response_export_values = []
  tags                   = local.tags
}

resource "azapi_resource" "gateway_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = "GatewaySubnet"
  parent_id = azapi_resource.virtual_network.id
  body = {
    properties = {
      addressPrefixes = ["10.0.0.0/27"]
    }
  }

  response_export_values = []
}

resource "azapi_resource" "workspace" {
  type      = "Microsoft.OperationalInsights/workspaces@2023-09-01"
  name      = "log-mlz-vgw-${random_string.suffix.result}"
  parent_id = azapi_resource.resource_group.id
  location  = local.location
  body = {
    properties = {
      retentionInDays = 30
      sku             = { name = "PerGB2018" }
    }
  }

  response_export_values = []
  tags                   = local.tags
}

module "virtual_network_gateway" {
  source = "../../"

  name          = "vgw-mlz-vgw-${random_string.suffix.result}"
  parent_id     = azapi_resource.resource_group.id
  location      = local.location
  subnet_id     = azapi_resource.gateway_subnet.id
  active_active = true
  bgp           = { asn = 65010 }
  ip_configurations = {
    ipconfig1 = { public_ip = { name = "pip-mlz-vgw-${random_string.suffix.result}-1" } }
    ipconfig2 = { public_ip = { name = "pip-mlz-vgw-${random_string.suffix.result}-2" } }
    ipconfig3 = { public_ip = { name = "pip-mlz-vgw-${random_string.suffix.result}-p2s" } }
  }
  point_to_site = {
    address_space = ["172.16.200.0/24"]
    entra_id      = { tenant_id = data.azapi_client_config.current.tenant_id }
  }
  local_network_gateways = {
    site-a = {
      name               = "lgw-mlz-vgw-${random_string.suffix.result}-site-a"
      gateway_ip_address = "203.0.113.20" # documentation range: the tunnel never comes up
      address_prefixes   = ["10.50.0.0/16"]
      bgp                = { asn = 65050, bgp_peering_address = "10.50.255.254" }
    }
  }
  connections = {
    site-a = {
      name                      = "con-mlz-vgw-${random_string.suffix.result}-site-a"
      local_network_gateway_key = "site-a"
      enable_bgp                = true
      diagnostic_settings = {
        workspace = {
          workspace_resource_id = azapi_resource.workspace.id
          metrics               = [{ category = "AllMetrics" }]
        }
      }
    }
  }
  connection_secrets = { site-a = ephemeral.random_password.shared_key.result }
  diagnostic_settings = {
    workspace = {
      workspace_resource_id = azapi_resource.workspace.id
      logs                  = [{ category_group = "allLogs" }]
      metrics               = [{ category = "AllMetrics" }]
    }
  }
  tags = local.tags
}
