mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/connections/con-test"
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
  location                   = "swedencentral"
  name                       = "con-test"
  parent_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
  virtual_network_gateway_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworkGateways/vgw-test"
  local_network_gateway_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/localNetworkGateways/lgw-test"
  shared_key                 = "key"
}

run "ipsec_defaults" {
  command = apply

  assert {
    condition     = azapi_resource.this.type == "Microsoft.Network/connections@2025-07-01" && azapi_resource.this.name == var.name && azapi_resource.this.parent_id == var.parent_id && azapi_resource.this.location == var.location
    error_message = "The connection should use the default resource type, name, parent_id and location."
  }
  assert {
    condition = jsonencode(azapi_resource.this.body) == jsonencode({
      properties = {
        connectionMode                 = "Default"
        connectionProtocol             = "IKEv2"
        connectionType                 = "IPsec"
        dpdTimeoutSeconds              = 45
        enableBgp                      = false
        gatewayCustomBgpIpAddresses    = []
        ipsecPolicies                  = []
        localNetworkGateway2           = { id = var.local_network_gateway_id, properties = {} }
        routingWeight                  = 0
        usePolicyBasedTrafficSelectors = false
        virtualNetworkGateway1         = { id = var.virtual_network_gateway_id, properties = {} }
      }
    })
    error_message = "An IPsec connection should send every IPsec setting, empty when unset, and no key in the body."
  }
  assert {
    condition     = jsonencode(azapi_resource.this.sensitive_body_version) == jsonencode({ "properties.sharedKey" = "1" })
    error_message = "The shared key should be versioned."
  }
  assert {
    condition = jsonencode(azapi_resource.this.replace_triggers_external_values) == jsonencode({
      connection_mode            = "Default"
      connection_protocol        = "IKEv2"
      dpd_timeout_seconds        = 45
      local_network_gateway_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/rg-test/providers/microsoft.network/localnetworkgateways/lgw-test"
      peer                       = null
      replace_triggers           = null
      type                       = "IPsec"
      virtual_network_gateway_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/rg-test/providers/microsoft.network/virtualnetworkgateways/vgw-test"
    })
    error_message = "The replacement triggers should be the type, gateway, site, IKE protocol, mode and DPD timeout."
  }
  assert {
    condition     = jsonencode(azapi_resource.this.locks) == jsonencode([var.virtual_network_gateway_id])
    error_message = "Writes should lock the gateway."
  }
}

run "ipsec_settings" {
  command = apply

  variables {
    enable_bgp                         = true
    connection_mode                    = "ResponderOnly"
    routing_weight                     = 10
    use_policy_based_traffic_selectors = true
    secret_version                     = "2"
    replace_triggers                   = { gateway = "x" }
    ipsec_policy = {
      dh_group         = "DHGroup14"
      ike_encryption   = "AES256"
      ike_integrity    = "SHA256"
      ipsec_encryption = "GCMAES256"
      ipsec_integrity  = "GCMAES256"
      pfs_group        = "PFS2048"
    }
    custom_bgp_addresses = [{
      ip_configuration_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworkGateways/vgw-test/ipConfigurations/ipconfig1"
      address             = "169.254.21.2"
    }]
  }

  assert {
    condition = jsonencode(azapi_resource.this.body.properties.ipsecPolicies) == jsonencode([{
      dhGroup             = "DHGroup14"
      ikeEncryption       = "AES256"
      ikeIntegrity        = "SHA256"
      ipsecEncryption     = "GCMAES256"
      ipsecIntegrity      = "GCMAES256"
      pfsGroup            = "PFS2048"
      saDataSizeKilobytes = 102400000
      saLifeTimeSeconds   = 27000
    }])
    error_message = "The IPsec policy should be sent with Azure's default SA size and lifetime."
  }
  assert {
    condition     = jsonencode(azapi_resource.this.body.properties.gatewayCustomBgpIpAddresses) == jsonencode([{ customBgpIpAddress = "169.254.21.2", ipConfigurationId = var.custom_bgp_addresses[0].ip_configuration_id }])
    error_message = "The custom BGP address should be sent per IP configuration."
  }
  assert {
    condition     = azapi_resource.this.body.properties.enableBgp && azapi_resource.this.body.properties.usePolicyBasedTrafficSelectors && azapi_resource.this.body.properties.routingWeight == 10 && azapi_resource.this.body.properties.connectionMode == "ResponderOnly"
    error_message = "BGP, policy-based traffic selectors, routing weight and mode should be sent."
  }
  assert {
    condition     = azapi_resource.this.sensitive_body_version["properties.sharedKey"] == "2" && jsonencode(azapi_resource.this.replace_triggers_external_values.replace_triggers) == jsonencode({ gateway = "x" })
    error_message = "The secret version and the caller's replacement triggers should reach the connection."
  }
}

run "vnet_to_vnet" {
  command = apply

  variables {
    type                            = "Vnet2Vnet"
    local_network_gateway_id        = null
    peer_virtual_network_gateway_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-other/providers/Microsoft.Network/virtualNetworkGateways/vgw-other"
  }

  assert {
    condition = jsonencode(azapi_resource.this.body.properties) == jsonencode({
      connectionProtocol     = "IKEv2"
      connectionType         = "Vnet2Vnet"
      enableBgp              = false
      ipsecPolicies          = []
      routingWeight          = 0
      virtualNetworkGateway1 = { id = var.virtual_network_gateway_id, properties = {} }
      virtualNetworkGateway2 = { id = var.peer_virtual_network_gateway_id, properties = {} }
    })
    error_message = "A Vnet2Vnet connection should name both gateways and send no IPsec-only settings."
  }
  assert {
    condition     = jsonencode(azapi_resource.this.locks) == jsonencode([var.virtual_network_gateway_id, var.peer_virtual_network_gateway_id]) && azapi_resource.this.replace_triggers_external_values.peer == lower(var.peer_virtual_network_gateway_id)
    error_message = "Writes should lock both gateways, and the peer should be a replacement trigger."
  }
}

run "expressroute" {
  command = apply

  variables {
    type                         = "ExpressRoute"
    local_network_gateway_id     = null
    shared_key                   = null
    express_route_circuit_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteCircuits/erc-test"
    express_route_gateway_bypass = true
    authorization_key            = "authorization"
  }

  assert {
    condition = jsonencode(azapi_resource.this.body.properties) == jsonencode({
      connectionType            = "ExpressRoute"
      expressRouteGatewayBypass = true
      peer                      = { id = var.express_route_circuit_id }
      routingWeight             = 0
      virtualNetworkGateway1    = { id = var.virtual_network_gateway_id, properties = {} }
    })
    error_message = "An ExpressRoute connection should name the circuit and send no VPN settings."
  }
  assert {
    condition     = jsonencode(azapi_resource.this.sensitive_body_version) == jsonencode({ "properties.authorizationKey" = "1" }) && azapi_resource.this.replace_triggers_external_values.peer == lower(var.express_route_circuit_id)
    error_message = "The authorization key should be versioned and the circuit a replacement trigger."
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
    resource_types = { network_connections = "Microsoft.Network/connections@2024-05-01" }
    retry          = { interval_seconds = 5 }
    timeouts       = { create = "45m" }
    tags           = { environment = "test" }
  }

  assert {
    condition     = azapi_resource.this.type == "Microsoft.Network/connections@2024-05-01" && azapi_resource.this.tags == tomap({ environment = "test" })
    error_message = "resource_types and tags should reach the connection."
  }
  assert {
    condition     = azapi_resource.this.retry.error_message_regex == tolist(["AnotherOperationInProgress"]) && azapi_resource.this.retry.interval_seconds == 5 && azapi_resource.this.timeouts.create == "45m"
    error_message = "retry should keep the defaults of fields not overridden, and timeouts should reach the resource."
  }
}

run "invalid_name" {
  command = plan

  variables {
    name = "con-"
  }

  expect_failures = [var.name]
}

run "invalid_gateway_id" {
  command = plan

  variables {
    virtual_network_gateway_id = var.local_network_gateway_id
  }

  expect_failures = [var.virtual_network_gateway_id]
}

run "invalid_type" {
  command = plan

  variables {
    type = "VPNClient"
  }

  expect_failures = [var.type]
}

run "ipsec_without_local_network_gateway" {
  command = plan

  variables {
    local_network_gateway_id = null
  }

  expect_failures = [var.type]
}

run "ipsec_without_shared_key" {
  command = plan

  variables {
    shared_key = null
  }

  expect_failures = [var.shared_key]
}

run "expressroute_with_shared_key" {
  command = plan

  variables {
    type                     = "ExpressRoute"
    local_network_gateway_id = null
    express_route_circuit_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/expressRouteCircuits/erc-test"
  }

  expect_failures = [var.shared_key]
}

run "authorization_key_on_ipsec" {
  command = plan

  variables {
    authorization_key = "authorization"
  }

  expect_failures = [var.authorization_key]
}

run "invalid_dpd_timeout" {
  command = plan

  variables {
    dpd_timeout_seconds = 5
  }

  expect_failures = [var.dpd_timeout_seconds]
}

run "invalid_routing_weight" {
  command = plan

  variables {
    routing_weight = 40000
  }

  expect_failures = [var.routing_weight]
}

run "invalid_custom_bgp_address" {
  command = plan

  variables {
    custom_bgp_addresses = [{
      ip_configuration_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworkGateways/vgw-test/ipConfigurations/ipconfig1"
      address             = "169.254.0.1"
    }]
  }

  expect_failures = [var.custom_bgp_addresses]
}

run "invalid_custom_bgp_ip_configuration_id" {
  command = plan

  variables {
    custom_bgp_addresses = [{ ip_configuration_id = var.virtual_network_gateway_id, address = "169.254.21.2" }]
  }

  expect_failures = [var.custom_bgp_addresses]
}

run "policy_based_selectors_without_policy" {
  command = plan

  variables {
    use_policy_based_traffic_selectors = true
  }

  expect_failures = [var.use_policy_based_traffic_selectors]
}

run "diagnostic_logs" {
  command = plan

  variables {
    diagnostic_settings = {
      workspace = {
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test"
        logs                  = [{ category_group = "allLogs" }]
      }
    }
  }

  expect_failures = [var.diagnostic_settings]
}
