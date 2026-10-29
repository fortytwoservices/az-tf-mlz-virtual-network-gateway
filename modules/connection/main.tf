resource "azapi_resource" "this" {
  type      = var.resource_types.network_connections
  name      = var.name
  parent_id = var.parent_id
  location  = var.location
  # Every setting of the connection type is sent, empty when unset: azapi compares only the keys in the
  # body, so a setting left out when removed would stay in Azure. merge() skips null, which unlike {}
  # unifies with either object type. The schema requires `properties` in a referenced gateway; an empty
  # one has no keys to compare.
  body = {
    properties = merge(
      {
        connectionType         = var.type
        virtualNetworkGateway1 = { id = var.virtual_network_gateway_id, properties = {} }
        routingWeight          = var.routing_weight
      },
      var.type == "ExpressRoute" ? null : {
        connectionProtocol = var.connection_protocol
        enableBgp          = var.enable_bgp
        ipsecPolicies = var.ipsec_policy == null ? [] : [{
          dhGroup             = var.ipsec_policy.dh_group
          ikeEncryption       = var.ipsec_policy.ike_encryption
          ikeIntegrity        = var.ipsec_policy.ike_integrity
          ipsecEncryption     = var.ipsec_policy.ipsec_encryption
          ipsecIntegrity      = var.ipsec_policy.ipsec_integrity
          pfsGroup            = var.ipsec_policy.pfs_group
          saDataSizeKilobytes = var.ipsec_policy.sa_data_size_kilobytes
          saLifeTimeSeconds   = var.ipsec_policy.sa_lifetime_seconds
        }]
      },
      var.type == "IPsec" ? {
        localNetworkGateway2           = { id = var.local_network_gateway_id, properties = {} }
        connectionMode                 = var.connection_mode
        dpdTimeoutSeconds              = var.dpd_timeout_seconds
        usePolicyBasedTrafficSelectors = var.use_policy_based_traffic_selectors
        gatewayCustomBgpIpAddresses = [for address in var.custom_bgp_addresses : {
          ipConfigurationId  = address.ip_configuration_id
          customBgpIpAddress = address.address
        }]
      } : null,
      var.type == "Vnet2Vnet" ? {
        virtualNetworkGateway2 = { id = var.peer_virtual_network_gateway_id, properties = {} }
      } : null,
      var.type == "ExpressRoute" ? {
        peer                      = { id = var.express_route_circuit_id }
        expressRouteGatewayBypass = var.express_route_gateway_bypass
      } : null,
    )
  }
  # The keys are write-only: sent on create and whenever `secret_version` changes, never stored or read.
  # The version cannot depend on whether a key is set (the keys are ephemeral), so it is keyed by type.
  sensitive_body         = var.type == "ExpressRoute" ? (var.authorization_key == null ? null : { properties = { authorizationKey = var.authorization_key } }) : { properties = { sharedKey = var.shared_key } }
  sensitive_body_version = { (var.type == "ExpressRoute" ? "properties.authorizationKey" : "properties.sharedKey") = var.secret_version }
  ignore_body_changes    = length(var.ignore_body_changes.network_connections) > 0 ? var.ignore_body_changes.network_connections : null
  # Azure writes a connection through its gateways: one at a time per gateway.
  locks = compact([var.virtual_network_gateway_id, var.peer_virtual_network_gateway_id])
  # What azurerm marks ForceNew (checked 2026-10-28): the type, the gateways and the circuit, the IKE
  # protocol, the connection mode and the DPD timeout. Also the local network gateway, which azurerm
  # updates in place but Azure refuses to change (GatewayConnectionEndpointCannotBeChanged, sandbox
  # 2026-10-28), and `replace_triggers`, the gateway's own. Compared as inputs, so Azure's casing of IDs cannot replace
  # anything. The keys are part of the contract: a new key would replace every deployed connection.
  replace_triggers_external_values = {
    connection_protocol        = var.type == "ExpressRoute" ? null : var.connection_protocol
    connection_mode            = var.type == "IPsec" ? var.connection_mode : null
    dpd_timeout_seconds        = var.type == "IPsec" ? var.dpd_timeout_seconds : null
    local_network_gateway_id   = var.type == "IPsec" ? try(lower(var.local_network_gateway_id), null) : null
    peer                       = try(lower(var.type == "Vnet2Vnet" ? var.peer_virtual_network_gateway_id : var.express_route_circuit_id), null)
    replace_triggers           = var.replace_triggers
    type                       = var.type
    virtual_network_gateway_id = lower(var.virtual_network_gateway_id)
  }
  response_export_values = []
  retry                  = var.retry
  tags                   = var.tags

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }
}
