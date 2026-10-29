resource "azapi_resource" "this" {
  type      = var.resource_types.network_local_network_gateways
  name      = var.name
  parent_id = var.parent_id
  location  = var.location
  # Every setting is sent, null or empty when unset: azapi compares only the keys in the body, so a
  # setting left out when removed would stay in Azure. Azure reports neither `fqdn` nor `bgpSettings`
  # when they are unset, and a PUT with them null removes them (sandbox, 2026-10-28).
  body = {
    properties = {
      gatewayIpAddress         = var.gateway_ip_address
      fqdn                     = var.fqdn
      localNetworkAddressSpace = { addressPrefixes = var.address_prefixes }
      bgpSettings = var.bgp == null ? null : {
        asn               = var.bgp.asn
        bgpPeeringAddress = var.bgp.bgp_peering_address
        peerWeight        = var.bgp.peer_weight
      }
    }
  }
  ignore_body_changes    = length(var.ignore_body_changes.network_local_network_gateways) > 0 ? var.ignore_body_changes.network_local_network_gateways : null
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
