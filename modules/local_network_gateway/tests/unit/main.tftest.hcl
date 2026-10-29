mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/localNetworkGateways/lgw-test"
    }
  }
  mock_data "azapi_resource_list" {
    defaults = {
      output = {
        results = [
          {
            id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
            role_name = "Reader"
          }
        ]
      }
    }
  }
}
mock_provider "random" {}
mock_provider "time" {}

variables {
  location           = "swedencentral"
  name               = "lgw-test"
  parent_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
  gateway_ip_address = "203.0.113.20"
  address_prefixes   = ["10.50.0.0/16"]
}

run "defaults" {
  command = apply

  assert {
    condition     = azapi_resource.this.type == "Microsoft.Network/localNetworkGateways@2025-07-01" && azapi_resource.this.name == var.name && azapi_resource.this.parent_id == var.parent_id && azapi_resource.this.location == var.location
    error_message = "The local network gateway should use the default resource type, name, parent_id and location."
  }
  assert {
    condition = jsonencode(azapi_resource.this.body) == jsonencode({
      properties = {
        bgpSettings              = null
        fqdn                     = null
        gatewayIpAddress         = "203.0.113.20"
        localNetworkAddressSpace = { addressPrefixes = ["10.50.0.0/16"] }
      }
    })
    error_message = "Every setting should be sent, null when unset."
  }
  assert {
    condition     = output.resource_id == azapi_resource.this.id && output.name == var.name
    error_message = "The outputs should give the ID and name."
  }
}

run "fqdn_and_bgp" {
  command = apply

  variables {
    gateway_ip_address = null
    fqdn               = "vpn.example.com"
    address_prefixes   = []
    bgp                = { asn = 65050, bgp_peering_address = "169.254.21.1", peer_weight = 5 }
  }

  assert {
    condition = jsonencode(azapi_resource.this.body.properties) == jsonencode({
      bgpSettings              = { asn = 65050, bgpPeeringAddress = "169.254.21.1", peerWeight = 5 }
      fqdn                     = "vpn.example.com"
      gatewayIpAddress         = null
      localNetworkAddressSpace = { addressPrefixes = [] }
    })
    error_message = "An FQDN with BGP and no address ranges."
  }
}

run "interfaces" {
  command = apply

  variables {
    lock = { kind = "CanNotDelete" }
    role_assignments = {
      reader = { role_definition_id_or_name = "Reader", principal_id = "11111111-1111-1111-1111-111111111111" }
    }
  }

  assert {
    condition     = module.interfaces.lock_resource_id != null && length(module.interfaces.role_assignment_resource_ids) == 1
    error_message = "The lock and the role assignment should be created."
  }
}

run "azapi_settings" {
  command = apply

  variables {
    resource_types = { network_local_network_gateways = "Microsoft.Network/localNetworkGateways@2024-05-01" }
    retry          = { interval_seconds = 5 }
    timeouts       = { create = "45m" }
    tags           = { environment = "test" }
  }

  assert {
    condition     = azapi_resource.this.type == "Microsoft.Network/localNetworkGateways@2024-05-01" && azapi_resource.this.tags == tomap({ environment = "test" })
    error_message = "resource_types and tags should reach the local network gateway."
  }
  assert {
    condition     = azapi_resource.this.retry.error_message_regex == tolist(["AnotherOperationInProgress"]) && azapi_resource.this.retry.interval_seconds == 5 && azapi_resource.this.timeouts.create == "45m"
    error_message = "retry should keep the defaults of fields not overridden, and timeouts should reach the resource."
  }
}

run "invalid_name" {
  command = plan

  variables {
    name = "lgw-"
  }

  expect_failures = [var.name]
}

run "invalid_parent_id" {
  command = plan

  variables {
    parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000"
  }

  expect_failures = [var.parent_id]
}

run "both_ip_address_and_fqdn" {
  command = plan

  variables {
    fqdn = "vpn.example.com"
  }

  expect_failures = [var.gateway_ip_address]
}

run "neither_ip_address_nor_fqdn" {
  command = plan

  variables {
    gateway_ip_address = null
  }

  expect_failures = [var.gateway_ip_address]
}

run "invalid_ip_address" {
  command = plan

  variables {
    gateway_ip_address = "2001:db8::1"
  }

  expect_failures = [var.gateway_ip_address]
}

run "invalid_address_prefix" {
  command = plan

  variables {
    address_prefixes = ["10.50.0.0"]
  }

  expect_failures = [var.address_prefixes]
}

run "no_address_prefixes_without_bgp" {
  command = plan

  variables {
    address_prefixes = []
  }

  expect_failures = [var.address_prefixes]
}

run "reserved_asn" {
  command = plan

  variables {
    bgp = { asn = 65515, bgp_peering_address = "10.50.255.254" }
  }

  expect_failures = [var.bgp]
}

run "invalid_bgp_peering_address" {
  command = plan

  variables {
    bgp = { asn = 65050, bgp_peering_address = "10.50.255.254/32" }
  }

  expect_failures = [var.bgp]
}

run "invalid_peer_weight" {
  command = plan

  variables {
    bgp = { asn = 65050, bgp_peering_address = "10.50.255.254", peer_weight = 200 }
  }

  expect_failures = [var.bgp]
}
