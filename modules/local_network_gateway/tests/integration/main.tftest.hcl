# Real Azure, no mocks: ARM_SUBSCRIPTION_ID=<test subscription> scripts/integration.sh modules/local_network_gateway
# A local network gateway costs nothing. Proves the default API version and body are accepted, and that
# switching from an IP address and address ranges to an FQDN with BGP only reaches Azure, under the
# resource's own lock.

run "setup" {
  module {
    source = "./tests/integration/setup"
  }
}

run "create" {
  variables {
    name               = "lgw-mlz-it-${run.setup.suffix}"
    parent_id          = run.setup.resource_group_id
    location           = run.setup.location
    gateway_ip_address = "203.0.113.20"
    address_prefixes   = ["10.50.0.0/16", "10.51.0.0/16"]
    lock               = { kind = "CanNotDelete" }
    role_assignments = {
      reader = { role_definition_id_or_name = "Reader", principal_id = run.setup.object_id }
    }
    tags = { test = "integration" }
  }

  assert {
    condition     = endswith(output.resource_id, "/localNetworkGateways/lgw-mlz-it-${run.setup.suffix}")
    error_message = "The local network gateway should be created."
  }
}

run "fqdn_and_bgp_only" {
  variables {
    name      = "lgw-mlz-it-${run.setup.suffix}"
    parent_id = run.setup.resource_group_id
    location  = run.setup.location
    fqdn      = "vpn.example.com"
    bgp       = { asn = 65050, bgp_peering_address = "169.254.21.1", peer_weight = 5 }
    lock      = { kind = "CanNotDelete" }
    role_assignments = {
      reader = { role_definition_id_or_name = "Reader", principal_id = run.setup.object_id }
    }
    tags = { test = "integration" }
  }
}

run "read" {
  module {
    source = "./tests/integration/read"
  }

  variables {
    resource_id = run.create.resource_id
  }

  assert {
    condition     = output.properties.fqdn == "vpn.example.com" && try(output.properties.gatewayIpAddress, null) == null
    error_message = "Azure should hold the FQDN and no IP address."
  }
  assert {
    condition     = length(try(output.properties.localNetworkAddressSpace.addressPrefixes, [])) == 0
    error_message = "Azure should hold no address ranges."
  }
  assert {
    condition     = output.properties.bgpSettings.asn == 65050 && output.properties.bgpSettings.bgpPeeringAddress == "169.254.21.1" && output.properties.bgpSettings.peerWeight == 5
    error_message = "Azure should hold the BGP settings."
  }
}
