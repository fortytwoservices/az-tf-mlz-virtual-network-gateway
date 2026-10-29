mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworkGateways/vgw-test"
      output = {
        properties = {
          ipAddress = "203.0.113.10"
          bgpSettings = {
            asn        = 65515
            peerWeight = 0
            bgpPeeringAddresses = [{
              ipconfigurationId     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworkGateways/vgw-test/ipConfigurations/ipconfig1"
              defaultBgpIpAddresses = ["10.0.0.30"]
              customBgpIpAddresses  = []
              tunnelIpAddresses     = ["203.0.113.10"]
            }]
          }
        }
      }
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
  location  = "swedencentral"
  name      = "vgw-test"
  parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
  subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-hub/subnets/GatewaySubnet"
  ip_configurations = {
    ipconfig1 = { public_ip = { name = "pip-vgw-test-1" } }
  }
}

run "defaults" {
  command = apply

  assert {
    condition     = azapi_resource.this.type == "Microsoft.Network/virtualNetworkGateways@2025-07-01" && azapi_resource.this.name == var.name && azapi_resource.this.parent_id == var.parent_id && azapi_resource.this.location == var.location
    error_message = "The gateway should use the default resource type, name, parent_id and location."
  }
  assert {
    condition = jsonencode(azapi_resource.this.body) == jsonencode({
      properties = {
        activeActive = false
        bgpSettings = {
          asn = 65515
          bgpPeeringAddresses = [{
            customBgpIpAddresses = []
            ipconfigurationId    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworkGateways/vgw-test/ipConfigurations/ipconfig1"
          }]
          peerWeight = 0
        }
        enableBgp   = false
        gatewayType = "Vpn"
        ipConfigurations = [{
          name = "ipconfig1"
          properties = {
            privateIPAllocationMethod = "Dynamic"
            publicIPAddress           = { id = module.public_ip["ipconfig1"].resource_id }
            subnet                    = { id = var.subnet_id }
          }
        }]
        sku                    = { name = "VpnGw1AZ", tier = "VpnGw1AZ" }
        vpnClientConfiguration = null
        vpnGatewayGeneration   = "Generation1"
        vpnType                = "RouteBased"
      }
    })
    error_message = "An active-standby VpnGw1AZ (Generation1) gateway without BGP: Azure's BGP settings and one peering address entry sent, point-to-site null."
  }
  assert {
    condition = jsonencode(azapi_resource.this.replace_triggers_external_values) == jsonencode({
      gateway_type     = "Vpn"
      generation       = "Generation1"
      ip_configuration = { name = "ipconfig1", public_ip = jsonencode({ name = "pip-vgw-test-1", public_ip_prefix_id = null }) }
      subnet_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/rg-test/providers/microsoft.network/virtualnetworks/vnet-hub/subnets/gatewaysubnet"
    })
    error_message = "The replacement triggers should be the type, generation, first IP configuration and subnet."
  }
  assert {
    condition     = length(module.public_ip) == 1 && jsonencode(terraform_data.public_ip_destroy_order.input) == jsonencode({ ipconfig1 = module.public_ip["ipconfig1"].resource_id })
    error_message = "One public IP address should be created, and the destroy order should hold it."
  }
  assert {
    condition     = jsonencode(output.public_ip_address_ids) == jsonencode({ ipconfig1 = module.public_ip["ipconfig1"].resource_id }) && output.public_ip_addresses["ipconfig1"] == module.public_ip["ipconfig1"].ip_address
    error_message = "The outputs should give the created public IP address by IP configuration."
  }
  assert {
    condition     = output.bgp_settings.asn == 65515 && jsonencode(output.bgp_settings.peering_addresses) == jsonencode({ ipconfig1 = { default = ["10.0.0.30"], custom = [], tunnel = ["203.0.113.10"] } })
    error_message = "bgp_settings should give Azure's peering addresses by IP configuration name."
  }
  assert {
    condition     = azapi_resource.this.timeouts.create == "90m" && azapi_resource.this.timeouts.update == "90m" && azapi_resource.this.timeouts.delete == "90m" && azapi_resource.this.timeouts.read == null
    error_message = "Create, update and delete should default to 90 minutes."
  }
  assert {
    condition     = azapi_resource.this.retry.error_message_regex == tolist(["AnotherOperationInProgress"])
    error_message = "retry should default to AnotherOperationInProgress."
  }
  assert {
    condition     = length(module.local_network_gateway) == 0 && length(module.connection) == 0
    error_message = "No local network gateways or connections by default."
  }
}

run "active_active_with_bgp_and_point_to_site" {
  command = apply

  variables {
    sku            = "VpnGw2AZ"
    active_active  = true
    bgp            = { asn = 65010, peer_weight = 10 }
    vpn_generation = "Generation1"
    ip_configurations = {
      ipconfig1 = { public_ip = { name = "pip-vgw-test-1" }, apipa_addresses = ["169.254.21.2"] }
      ipconfig2 = { public_ip = { name = "pip-vgw-test-2" }, apipa_addresses = ["169.254.22.2"] }
      ipconfig3 = { public_ip_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/publicIPAddresses/pip-p2s" }
    }
    point_to_site = {
      address_space        = ["172.16.200.0/24"]
      protocols            = ["OpenVPN", "IkeV2"]
      entra_id             = { tenant_id = "22222222-2222-2222-2222-222222222222" }
      root_certificates    = { root-a = "MIIBdata" }
      revoked_certificates = { laptop = "0123456789ABCDEF0123456789ABCDEF01234567" }
    }
  }

  assert {
    condition = jsonencode(azapi_resource.this.body.properties.bgpSettings) == jsonencode({
      asn = 65010
      bgpPeeringAddresses = [
        { customBgpIpAddresses = ["169.254.21.2"], ipconfigurationId = local.ip_configuration_ids["ipconfig1"] },
        { customBgpIpAddresses = ["169.254.22.2"], ipconfigurationId = local.ip_configuration_ids["ipconfig2"] },
      ]
      peerWeight = 10
    }) && azapi_resource.this.body.properties.enableBgp && azapi_resource.this.body.properties.activeActive
    error_message = "BGP should carry the ASN, the weight and one peering address entry per instance, none for the point-to-site IP configuration."
  }
  assert {
    condition     = [for configuration in azapi_resource.this.body.properties.ipConfigurations : configuration.name] == ["ipconfig1", "ipconfig2", "ipconfig3"] && azapi_resource.this.body.properties.ipConfigurations[2].properties.publicIPAddress.id == var.ip_configurations.ipconfig3.public_ip_resource_id
    error_message = "The three IP configurations should be sent in name order, the third with the existing address."
  }
  assert {
    condition = jsonencode(azapi_resource.this.body.properties.vpnClientConfiguration) == jsonencode({
      aadAudience                  = "c632b3df-fb67-4d84-bdcf-b95ad541b5c8"
      aadIssuer                    = "https://sts.windows.net/22222222-2222-2222-2222-222222222222/"
      aadTenant                    = "https://login.microsoftonline.com/22222222-2222-2222-2222-222222222222"
      vpnAuthenticationTypes       = ["AAD", "Certificate"]
      vpnClientAddressPool         = { addressPrefixes = ["172.16.200.0/24"] }
      vpnClientProtocols           = ["OpenVPN", "IkeV2"]
      vpnClientRevokedCertificates = [{ name = "laptop", properties = { thumbprint = "0123456789ABCDEF0123456789ABCDEF01234567" } }]
      vpnClientRootCertificates    = [{ name = "root-a", properties = { publicCertData = "MIIBdata" } }]
    })
    error_message = "Point-to-site should carry Entra ID (public cloud URLs, the Microsoft-registered audience) and the certificates."
  }
  assert {
    condition     = azapi_resource.this.body.properties.sku.name == "VpnGw2AZ" && azapi_resource.this.body.properties.vpnGatewayGeneration == "Generation1"
    error_message = "An explicit generation should be sent."
  }
  assert {
    condition     = length(module.public_ip) == 2 && length(output.public_ip_address_ids) == 3
    error_message = "Two addresses should be created and the third given."
  }
}

run "generation_follows_the_sku" {
  command = plan

  variables {
    sku = "VpnGw3AZ"
  }

  assert {
    condition     = azapi_resource.this.body.properties.vpnGatewayGeneration == "Generation2" && azapi_resource.this.replace_triggers_external_values.generation == "Generation2"
    error_message = "Every SKU but VpnGw1AZ should default to Generation2."
  }
}

run "existing_public_ip" {
  command = apply

  variables {
    ip_configurations = {
      ipconfig1 = { public_ip_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/publicIPAddresses/pip-existing" }
    }
  }

  assert {
    condition     = length(module.public_ip) == 0 && output.public_ip_address_ids["ipconfig1"] == var.ip_configurations.ipconfig1.public_ip_resource_id && length(output.public_ip_addresses) == 0
    error_message = "An existing public IP address should be used, none created."
  }
  assert {
    condition     = azapi_resource.this.replace_triggers_external_values.ip_configuration.public_ip == "/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/rg-test/providers/microsoft.network/publicipaddresses/pip-existing"
    error_message = "The first public IP address's ID should be a replacement trigger, compared in lower case."
  }
}

run "express_route" {
  command = apply

  variables {
    gateway_type              = "ExpressRoute"
    sku                       = "ErGwScale"
    express_route_scale_units = { min = 2, max = 4 }
    ip_configurations         = {}
  }

  assert {
    condition = jsonencode(azapi_resource.this.body) == jsonencode({
      properties = {
        autoScaleConfiguration = { bounds = { max = 4, min = 2 } }
        gatewayType            = "ExpressRoute"
        ipConfigurations = [{
          name       = "default"
          properties = { privateIPAllocationMethod = "Dynamic", subnet = { id = var.subnet_id } }
        }]
        sku                  = { name = "ErGwScale", tier = "ErGwScale" }
        vpnGatewayGeneration = "None"
      }
    })
    error_message = "An ExpressRoute gateway: one IP configuration without a public IP address, scale units, generation None, no VPN settings."
  }
  assert {
    condition     = azapi_resource.this.replace_triggers_external_values.ip_configuration == null && azapi_resource.this.replace_triggers_external_values.generation == "None"
    error_message = "An ExpressRoute gateway's first IP configuration is not a trigger."
  }
  assert {
    condition     = length(module.public_ip) == 0 && length(output.public_ip_address_ids) == 0
    error_message = "An ExpressRoute gateway gets no public IP address from the module."
  }
}

run "local_network_gateways_and_connections" {
  command = apply

  variables {
    bgp = { asn = 65010 }
    ip_configurations = {
      ipconfig1 = { public_ip = { name = "pip-vgw-test-1" }, apipa_addresses = ["169.254.21.2"] }
    }
    local_network_gateways = {
      site-a = {
        name               = "lgw-site-a"
        gateway_ip_address = "203.0.113.20"
        bgp                = { asn = 65050, bgp_peering_address = "169.254.21.1" }
        lock               = { kind = "CanNotDelete" }
      }
    }
    connections = {
      site-a = {
        name                      = "con-site-a"
        local_network_gateway_key = "site-a"
        enable_bgp                = true
        custom_bgp_addresses      = { ipconfig1 = "169.254.21.2" }
      }
      site-b = {
        name                     = "con-site-b"
        local_network_gateway_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-other/providers/Microsoft.Network/localNetworkGateways/lgw-site-b"
      }
    }
    connection_secrets = { site-a = "key-a", site-b = "key-b" }
  }

  # The provider mock gives every resource the gateway's ID.
  override_module {
    target = module.local_network_gateway
    outputs = {
      name        = "lgw-site-a"
      resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/localNetworkGateways/lgw-site-a"
    }
  }

  assert {
    condition     = length(module.local_network_gateway) == 1
    error_message = "The local network gateway should be created."
  }
  assert {
    condition     = length(module.connection) == 2 && length(output.connection_resource_ids) == 2 && output.local_network_gateway_resource_ids["site-a"] == module.local_network_gateway["site-a"].resource_id
    error_message = "Both connections should be created, and the outputs should list them."
  }
}

run "interfaces" {
  command = apply

  variables {
    lock = { kind = "CanNotDelete" }
    role_assignments = {
      reader = { role_definition_id_or_name = "Reader", principal_id = "11111111-1111-1111-1111-111111111111" }
    }
    diagnostic_settings = {
      workspace = {
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test"
        logs                  = [{ category_group = "allLogs" }]
        metrics               = [{ category = "AllMetrics" }]
      }
    }
  }

  assert {
    condition     = module.interfaces.lock_resource_id != null && length(module.interfaces.role_assignment_resource_ids) == 1 && length(module.interfaces.diagnostic_setting_resource_ids) == 1
    error_message = "The lock, the role assignment and the diagnostic setting should be created."
  }
}

run "azapi_settings" {
  command = apply

  variables {
    resource_types = { network_virtual_network_gateways = "Microsoft.Network/virtualNetworkGateways@2024-05-01" }
    retry          = { error_message_regex = ["Conflict"], interval_seconds = 5 }
    timeouts       = { create = "120m", delete = "60m" }
    tags           = { environment = "test" }
  }

  assert {
    condition     = azapi_resource.this.type == "Microsoft.Network/virtualNetworkGateways@2024-05-01"
    error_message = "resource_types should override the gateway's type."
  }
  assert {
    condition     = azapi_resource.this.retry.error_message_regex == tolist(["Conflict"]) && azapi_resource.this.retry.interval_seconds == 5 && azapi_resource.this.retry.max_interval_seconds == 300
    error_message = "retry should keep the defaults of fields not overridden."
  }
  assert {
    condition     = azapi_resource.this.timeouts.create == "120m" && azapi_resource.this.timeouts.update == "90m" && azapi_resource.this.timeouts.delete == "60m"
    error_message = "timeouts should keep the defaults of fields not overridden."
  }
  assert {
    condition     = azapi_resource.this.tags == tomap({ environment = "test" })
    error_message = "tags should reach the gateway."
  }
}

run "invalid_name" {
  command = plan

  variables {
    name = "-vgw"
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

run "wrong_subnet" {
  command = plan

  variables {
    subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-hub/subnets/default"
  }

  expect_failures = [var.subnet_id]
}

run "invalid_gateway_type" {
  command = plan

  variables {
    gateway_type = "LocalGateway"
  }

  expect_failures = [var.gateway_type]
}

run "non_az_sku" {
  command = plan

  variables {
    sku = "VpnGw1"
  }

  expect_failures = [var.sku]
}

run "expressroute_sku_on_vpn" {
  command = plan

  variables {
    sku = "ErGw1AZ"
  }

  expect_failures = [var.sku]
}

run "generation1_on_vpngw4az" {
  command = plan

  variables {
    sku            = "VpnGw4AZ"
    vpn_generation = "Generation1"
  }

  expect_failures = [var.vpn_generation]
}

run "generation2_on_vpngw1az" {
  command = plan

  variables {
    vpn_generation = "Generation2"
  }

  expect_failures = [var.vpn_generation]
}

run "no_ip_configuration" {
  command = plan

  variables {
    ip_configurations = {}
  }

  expect_failures = [var.ip_configurations]
}

run "active_active_with_one_ip_configuration" {
  command = plan

  variables {
    active_active = true
  }

  expect_failures = [var.ip_configurations]
}

run "active_active_point_to_site_without_third_ip_configuration" {
  command = plan

  variables {
    active_active = true
    ip_configurations = {
      ipconfig1 = { public_ip = { name = "pip-vgw-test-1" } }
      ipconfig2 = { public_ip = { name = "pip-vgw-test-2" } }
    }
    point_to_site = { address_space = ["172.16.200.0/24"], entra_id = { tenant_id = "22222222-2222-2222-2222-222222222222" } }
  }

  expect_failures = [var.ip_configurations]
}

run "both_public_ips" {
  command = plan

  variables {
    ip_configurations = {
      ipconfig1 = {
        public_ip             = { name = "pip-vgw-test-1" }
        public_ip_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/publicIPAddresses/pip-existing"
      }
    }
  }

  expect_failures = [var.ip_configurations]
}

run "no_public_ip" {
  command = plan

  variables {
    ip_configurations = { ipconfig1 = {} }
  }

  expect_failures = [var.ip_configurations]
}

run "invalid_public_ip_resource_id" {
  command = plan

  variables {
    ip_configurations = { ipconfig1 = { public_ip_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test" } }
  }

  expect_failures = [var.ip_configurations]
}

run "apipa_out_of_range" {
  command = plan

  variables {
    bgp               = {}
    ip_configurations = { ipconfig1 = { public_ip = { name = "pip-vgw-test-1" }, apipa_addresses = ["169.254.20.1"] } }
  }

  expect_failures = [var.ip_configurations]
}

run "apipa_without_bgp" {
  command = plan

  variables {
    ip_configurations = { ipconfig1 = { public_ip = { name = "pip-vgw-test-1" }, apipa_addresses = ["169.254.21.2"] } }
  }

  expect_failures = [var.ip_configurations]
}

run "apipa_on_point_to_site_ip_configuration" {
  command = plan

  variables {
    active_active = true
    bgp           = {}
    ip_configurations = {
      ipconfig1 = { public_ip = { name = "pip-vgw-test-1" } }
      ipconfig2 = { public_ip = { name = "pip-vgw-test-2" } }
      ipconfig3 = { public_ip = { name = "pip-vgw-test-3" }, apipa_addresses = ["169.254.21.10"] }
    }
    point_to_site = { address_space = ["172.16.200.0/24"], entra_id = { tenant_id = "22222222-2222-2222-2222-222222222222" } }
  }

  expect_failures = [var.ip_configurations]
}

run "reserved_asn" {
  command = plan

  variables {
    bgp = { asn = 65517 }
  }

  expect_failures = [var.bgp]
}

run "iana_reserved_asn" {
  command = plan

  variables {
    bgp = { asn = 64500 }
  }

  expect_failures = [var.bgp]
}

run "azure_default_asn_allowed" {
  command = plan

  variables {
    bgp = { asn = 65515 }
  }

  assert {
    condition     = azapi_resource.this.body.properties.bgpSettings.asn == 65515 && azapi_resource.this.body.properties.enableBgp
    error_message = "65515, Azure's own ASN, should be allowed on the gateway."
  }
}

run "invalid_peer_weight" {
  command = plan

  variables {
    bgp = { peer_weight = 101 }
  }

  expect_failures = [var.bgp]
}

run "vpn_settings_on_expressroute" {
  command = plan

  variables {
    gateway_type      = "ExpressRoute"
    sku               = "ErGw1AZ"
    ip_configurations = {}
    active_active     = true
    bgp               = {}
    vpn_generation    = "Generation2"
    point_to_site     = { address_space = ["172.16.200.0/24"], entra_id = { tenant_id = "22222222-2222-2222-2222-222222222222" } }
  }

  expect_failures = [var.active_active, var.bgp, var.vpn_generation, var.point_to_site]
}

run "ip_configurations_on_expressroute" {
  command = plan

  variables {
    gateway_type = "ExpressRoute"
    sku          = "ErGw1AZ"
  }

  expect_failures = [var.ip_configurations]
}

run "point_to_site_without_authentication" {
  command = plan

  variables {
    point_to_site = { address_space = ["172.16.200.0/24"] }
  }

  expect_failures = [var.point_to_site]
}

run "entra_id_without_openvpn" {
  command = plan

  variables {
    point_to_site = { address_space = ["172.16.200.0/24"], protocols = ["IkeV2"], entra_id = { tenant_id = "22222222-2222-2222-2222-222222222222" } }
  }

  expect_failures = [var.point_to_site]
}

run "invalid_point_to_site_protocol" {
  command = plan

  variables {
    point_to_site = { address_space = ["172.16.200.0/24"], protocols = ["L2TP"], root_certificates = { root = "MIIB" } }
  }

  expect_failures = [var.point_to_site]
}

run "openvpn_with_sstp" {
  command = plan

  variables {
    point_to_site = { address_space = ["172.16.200.0/24"], protocols = ["OpenVPN", "SSTP"], root_certificates = { root = "MIIB" } }
  }

  expect_failures = [var.point_to_site]
}

run "sstp_with_ikev2" {
  command = plan

  variables {
    point_to_site = { address_space = ["172.16.200.0/24"], protocols = ["IkeV2", "SSTP"], root_certificates = { root = "MIIB" } }
  }

  assert {
    condition     = jsonencode(azapi_resource.this.body.properties.vpnClientConfiguration.vpnClientProtocols) == jsonencode(["IkeV2", "SSTP"])
    error_message = "SSTP with IKEv2 should be allowed."
  }
}

run "invalid_point_to_site_address_space" {
  command = plan

  variables {
    point_to_site = { address_space = ["172.16.200.0"], root_certificates = { root = "MIIB" } }
  }

  expect_failures = [var.point_to_site]
}

run "scale_units_without_ergwscale" {
  command = plan

  variables {
    gateway_type              = "ExpressRoute"
    sku                       = "ErGw1AZ"
    ip_configurations         = {}
    express_route_scale_units = { min = 1, max = 1 }
  }

  expect_failures = [var.express_route_scale_units]
}

run "ergwscale_without_scale_units" {
  command = plan

  variables {
    gateway_type      = "ExpressRoute"
    sku               = "ErGwScale"
    ip_configurations = {}
  }

  expect_failures = [var.express_route_scale_units]
}

run "autoscale_from_one_unit" {
  command = plan

  variables {
    gateway_type              = "ExpressRoute"
    sku                       = "ErGwScale"
    ip_configurations         = {}
    express_route_scale_units = { min = 1, max = 4 }
  }

  expect_failures = [var.express_route_scale_units]
}

run "too_many_scale_units" {
  command = plan

  variables {
    gateway_type              = "ExpressRoute"
    sku                       = "ErGwScale"
    ip_configurations         = {}
    express_route_scale_units = { min = 41, max = 41 }
  }

  expect_failures = [var.express_route_scale_units]
}

run "unknown_local_network_gateway_key" {
  command = plan

  variables {
    connections        = { site-a = { name = "con-site-a", local_network_gateway_key = "site-a" } }
    connection_secrets = { site-a = "key-a" }
  }

  expect_failures = [var.connections]
}

run "ipsec_connection_with_both_local_network_gateways" {
  command = plan

  variables {
    local_network_gateways = { site-a = { name = "lgw-site-a", gateway_ip_address = "203.0.113.20", address_prefixes = ["10.50.0.0/16"] } }
    connections = {
      site-a = {
        name                      = "con-site-a"
        local_network_gateway_key = "site-a"
        local_network_gateway_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-other/providers/Microsoft.Network/localNetworkGateways/lgw-site-b"
      }
    }
    connection_secrets = { site-a = "key-a" }
  }

  expect_failures = [var.connections]
}

run "expressroute_connection_on_vpn_gateway" {
  command = plan

  variables {
    connections = {
      circuit = {
        name                     = "con-circuit"
        type                     = "ExpressRoute"
        express_route_circuit_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteCircuits/erc-test"
      }
    }
  }

  expect_failures = [var.connections]
}

run "custom_bgp_address_not_on_the_gateway" {
  command = plan

  variables {
    bgp                    = {}
    ip_configurations      = { ipconfig1 = { public_ip = { name = "pip-vgw-test-1" }, apipa_addresses = ["169.254.21.2"] } }
    local_network_gateways = { site-a = { name = "lgw-site-a", gateway_ip_address = "203.0.113.20", address_prefixes = ["10.50.0.0/16"] } }
    connections = {
      site-a = { name = "con-site-a", local_network_gateway_key = "site-a", custom_bgp_addresses = { ipconfig1 = "169.254.21.6" } }
    }
    connection_secrets = { site-a = "key-a" }
  }

  expect_failures = [var.connections]
}

run "invalid_lock_kind" {
  command = plan

  variables {
    lock = { kind = "Delete" }
  }

  expect_failures = [var.lock]
}
