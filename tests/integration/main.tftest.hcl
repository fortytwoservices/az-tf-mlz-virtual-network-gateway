# Real Azure, no mocks: ARM_SUBSCRIPTION_ID=<test subscription> scripts/integration.sh .
# One VpnGw1AZ gateway, billed by the hour while it exists: the run destroys it at the end. Each gateway
# write takes up to 45 minutes, so the whole run takes about three hours.
# Proves what mocks cannot: the default API version and bodies are accepted; an active-standby gateway
# with BGP, certificate point-to-site, a site and its connection, under a lock with diagnostics, is
# switched in place to active-active with a third (point-to-site) public IP address, Entra ID and custom
# APIPA addresses; its site is renamed (Azure does not move a connection, so it is replaced, with custom
# BGP addresses); then, the custom BGP addresses removed, it goes back to active-standby without
# point-to-site, where the gateway lets go of two created public IP addresses before they are deleted,
# in one apply.

run "setup" {
  module {
    source = "./tests/integration/setup"
  }
}

variables {
  name      = "vgw-mlz-it-${run.setup.suffix}"
  parent_id = run.setup.resource_group_id
  location  = run.setup.location
  subnet_id = run.setup.gateway_subnet_id
  sku       = "VpnGw1AZ"
  bgp       = { asn = 65010 }
  diagnostic_settings = {
    workspace = {
      workspace_resource_id = run.setup.workspace_id
      logs                  = [{ category_group = "allLogs" }]
      metrics               = [{ category = "AllMetrics" }]
    }
  }
  lock               = { kind = "CanNotDelete" }
  connection_secrets = { site = "integration-test-key-not-a-secret" }
  local_network_gateways = {
    site = {
      name               = "lgw-mlz-it-${run.setup.suffix}-a"
      gateway_ip_address = "203.0.113.20"
      address_prefixes   = ["10.50.0.0/16"]
      bgp                = { asn = 65050, bgp_peering_address = "10.50.255.254" }
    }
  }
  connections = {
    site = {
      name                      = "con-mlz-it-${run.setup.suffix}"
      local_network_gateway_key = "site"
      enable_bgp                = true
      diagnostic_settings = {
        workspace = {
          workspace_resource_id = run.setup.workspace_id
          metrics               = [{ category = "AllMetrics" }]
        }
      }
    }
  }
}

run "create" {
  variables {
    ip_configurations = {
      ipconfig1 = { public_ip = { name = "pip-mlz-it-${run.setup.suffix}-1" } }
    }
    point_to_site = {
      address_space     = ["172.16.200.0/24"]
      root_certificates = { root = run.setup.root_certificate_data }
    }
  }

  assert {
    condition     = output.bgp_settings.asn == 65010 && length(output.bgp_settings.peering_addresses["ipconfig1"].default) == 1
    error_message = "Azure should report the gateway's ASN and one BGP peer address from GatewaySubnet."
  }
  assert {
    condition     = length(output.public_ip_addresses) == 1 && length(output.connection_resource_ids) == 1
    error_message = "The gateway should have its public IP address and its connection."
  }
}

run "read_create" {
  module {
    source = "./tests/integration/read"
  }

  variables {
    gateway_id    = run.create.resource_id
    connection_id = run.create.connection_resource_ids["site"]
  }

  assert {
    condition     = !output.gateway.activeActive && length(output.gateway.ipConfigurations) == 1 && output.gateway.enableBgp
    error_message = "Azure should hold an active-standby gateway with BGP."
  }
  assert {
    condition     = jsonencode(output.gateway.vpnClientConfiguration.vpnAuthenticationTypes) == jsonencode(["Certificate"]) && length(output.gateway.vpnClientConfiguration.vpnClientRootCertificates) == 1
    error_message = "Azure should hold certificate point-to-site."
  }
  assert {
    condition     = output.connection.enableBgp && output.connection.connectionProtocol == "IKEv2" && output.connection.dpdTimeoutSeconds == 45
    error_message = "Azure should hold the connection with BGP, IKEv2 and a DPD timeout of 45 seconds."
  }
}

run "active_active_with_entra_id" {
  variables {
    active_active = true
    ip_configurations = {
      ipconfig1 = { public_ip = { name = "pip-mlz-it-${run.setup.suffix}-1" }, apipa_addresses = ["169.254.21.2"] }
      ipconfig2 = { public_ip = { name = "pip-mlz-it-${run.setup.suffix}-2" }, apipa_addresses = ["169.254.22.2"] }
      ipconfig3 = { public_ip = { name = "pip-mlz-it-${run.setup.suffix}-3" } }
    }
    point_to_site = {
      address_space     = ["172.16.200.0/24"]
      entra_id          = { tenant_id = run.setup.tenant_id }
      root_certificates = { root = run.setup.root_certificate_data }
    }
  }

  assert {
    condition     = length(output.public_ip_addresses) == 3 && output.public_ip_address_ids["ipconfig1"] == run.create.public_ip_address_ids["ipconfig1"]
    error_message = "Two public IP addresses should be added, the first kept."
  }
  assert {
    condition     = jsonencode(output.bgp_settings.peering_addresses["ipconfig1"].custom) == jsonencode(["169.254.21.2"]) && jsonencode(output.bgp_settings.peering_addresses["ipconfig2"].custom) == jsonencode(["169.254.22.2"])
    error_message = "Azure should report the custom APIPA addresses of both instances."
  }
}

run "read_active_active" {
  module {
    source = "./tests/integration/read"
  }

  variables {
    gateway_id    = run.create.resource_id
    connection_id = run.create.connection_resource_ids["site"]
  }

  assert {
    condition     = output.gateway.activeActive && length(output.gateway.ipConfigurations) == 3
    error_message = "Azure should hold an active-active gateway with three IP configurations."
  }
  assert {
    condition     = contains(output.gateway.vpnClientConfiguration.vpnAuthenticationTypes, "AAD") && endswith(output.gateway.vpnClientConfiguration.aadTenant, run.setup.tenant_id)
    error_message = "Azure should hold Entra ID point-to-site."
  }
}

run "renamed_site" {
  # The site becomes another local network gateway that peers over an APIPA address; the connection is
  # replaced on it, with the gateway's custom APIPA address per instance.
  variables {
    active_active = true
    ip_configurations = {
      ipconfig1 = { public_ip = { name = "pip-mlz-it-${run.setup.suffix}-1" }, apipa_addresses = ["169.254.21.2"] }
      ipconfig2 = { public_ip = { name = "pip-mlz-it-${run.setup.suffix}-2" }, apipa_addresses = ["169.254.22.2"] }
      ipconfig3 = { public_ip = { name = "pip-mlz-it-${run.setup.suffix}-3" } }
    }
    point_to_site = {
      address_space     = ["172.16.200.0/24"]
      entra_id          = { tenant_id = run.setup.tenant_id }
      root_certificates = { root = run.setup.root_certificate_data }
    }
    local_network_gateways = {
      site = {
        name               = "lgw-mlz-it-${run.setup.suffix}-b"
        gateway_ip_address = "203.0.113.20"
        bgp                = { asn = 65050, bgp_peering_address = "169.254.21.1" }
      }
    }
    connections = {
      site = {
        name                      = "con-mlz-it-${run.setup.suffix}"
        local_network_gateway_key = "site"
        enable_bgp                = true
        custom_bgp_addresses      = { ipconfig1 = "169.254.21.2", ipconfig2 = "169.254.22.2" }
        diagnostic_settings = {
          workspace = {
            workspace_resource_id = run.setup.workspace_id
            metrics               = [{ category = "AllMetrics" }]
          }
        }
      }
    }
  }

  assert {
    condition     = endswith(output.local_network_gateway_resource_ids["site"], "-b") && output.connection_resource_ids["site"] == run.create.connection_resource_ids["site"]
    error_message = "The site should be renamed, and the connection replaced under its name."
  }
}

run "read_renamed_site" {
  module {
    source = "./tests/integration/read"
  }

  variables {
    gateway_id    = run.create.resource_id
    connection_id = run.create.connection_resource_ids["site"]
  }

  assert {
    condition     = endswith(output.connection.localNetworkGateway2.id, "-b") && length(output.connection.gatewayCustomBgpIpAddresses) == 2
    error_message = "Azure should hold the connection on the renamed site, with its custom BGP addresses."
  }
}

run "custom_bgp_addresses_removed" {
  # Before instance 1 goes, the connection stops naming its IP configuration.
  variables {
    active_active = true
    ip_configurations = {
      ipconfig1 = { public_ip = { name = "pip-mlz-it-${run.setup.suffix}-1" }, apipa_addresses = ["169.254.21.2"] }
      ipconfig2 = { public_ip = { name = "pip-mlz-it-${run.setup.suffix}-2" }, apipa_addresses = ["169.254.22.2"] }
      ipconfig3 = { public_ip = { name = "pip-mlz-it-${run.setup.suffix}-3" } }
    }
    point_to_site = {
      address_space     = ["172.16.200.0/24"]
      entra_id          = { tenant_id = run.setup.tenant_id }
      root_certificates = { root = run.setup.root_certificate_data }
    }
    local_network_gateways = {
      site = {
        name               = "lgw-mlz-it-${run.setup.suffix}-b"
        gateway_ip_address = "203.0.113.20"
        bgp                = { asn = 65050, bgp_peering_address = "169.254.21.1" }
      }
    }
  }
}

run "back_to_active_standby_without_point_to_site" {
  variables {
    ip_configurations = {
      ipconfig1 = { public_ip = { name = "pip-mlz-it-${run.setup.suffix}-1" } }
    }
    local_network_gateways = {
      site = {
        name               = "lgw-mlz-it-${run.setup.suffix}-b"
        gateway_ip_address = "203.0.113.20"
        bgp                = { asn = 65050, bgp_peering_address = "169.254.21.1" }
      }
    }
  }

  assert {
    condition     = length(output.public_ip_address_ids) == 1 && output.public_ip_address_ids["ipconfig1"] == run.create.public_ip_address_ids["ipconfig1"]
    error_message = "The gateway should keep its first public IP address only."
  }
}

run "read_active_standby" {
  module {
    source = "./tests/integration/read"
  }

  variables {
    gateway_id    = run.create.resource_id
    connection_id = run.create.connection_resource_ids["site"]
  }

  assert {
    condition     = !output.gateway.activeActive && length(output.gateway.ipConfigurations) == 1
    error_message = "Azure should hold an active-standby gateway with one IP configuration."
  }
  assert {
    condition     = try(output.gateway.vpnClientConfiguration, null) == null || length(try(output.gateway.vpnClientConfiguration.vpnClientAddressPool.addressPrefixes, [])) == 0
    error_message = "Azure should hold no point-to-site configuration."
  }
  assert {
    condition     = length(output.connection.gatewayCustomBgpIpAddresses) == 0
    error_message = "The connection's custom BGP addresses should be removed."
  }
}
