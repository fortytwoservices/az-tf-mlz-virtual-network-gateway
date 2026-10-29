module "connection" {
  source   = "./modules/connection"
  for_each = var.connections

  name                       = each.value.name
  parent_id                  = var.parent_id
  location                   = var.location
  virtual_network_gateway_id = azapi_resource.this.id
  type                       = each.value.type
  # Chosen by the same test as the validation, so an existing ID that is unknown until apply never makes
  # Terraform index a local network gateway the module does not create.
  local_network_gateway_id           = each.value.local_network_gateway_key != null ? module.local_network_gateway[each.value.local_network_gateway_key].resource_id : each.value.local_network_gateway_id
  peer_virtual_network_gateway_id    = each.value.peer_virtual_network_gateway_id
  express_route_circuit_id           = each.value.express_route_circuit_id
  enable_bgp                         = each.value.enable_bgp
  connection_protocol                = each.value.connection_protocol
  connection_mode                    = each.value.connection_mode
  dpd_timeout_seconds                = each.value.dpd_timeout_seconds
  routing_weight                     = each.value.routing_weight
  use_policy_based_traffic_selectors = each.value.use_policy_based_traffic_selectors
  ipsec_policy                       = each.value.ipsec_policy
  express_route_gateway_bypass       = each.value.express_route_gateway_bypass
  custom_bgp_addresses = [for name, address in each.value.custom_bgp_addresses : {
    ip_configuration_id = local.ip_configuration_ids[name]
    address             = address
  }]
  shared_key          = each.value.type == "ExpressRoute" ? null : lookup(var.connection_secrets, each.key, null)
  authorization_key   = each.value.type == "ExpressRoute" ? lookup(var.connection_secrets, each.key, null) : null
  secret_version      = each.value.secret_version
  replace_triggers    = local.gateway_replace_triggers
  lock                = each.value.lock
  role_assignments    = each.value.role_assignments
  diagnostic_settings = each.value.diagnostic_settings
  tags                = var.tags
  resource_types      = var.resource_types.network_connections
  ignore_body_changes = var.ignore_body_changes.network_connections
  retry               = var.retry
  timeouts            = var.timeouts
}
