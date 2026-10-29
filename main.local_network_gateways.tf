module "local_network_gateway" {
  source   = "./modules/local_network_gateway"
  for_each = var.local_network_gateways

  name                = each.value.name
  parent_id           = var.parent_id
  location            = var.location
  gateway_ip_address  = each.value.gateway_ip_address
  fqdn                = each.value.fqdn
  address_prefixes    = each.value.address_prefixes
  bgp                 = each.value.bgp
  lock                = each.value.lock
  role_assignments    = each.value.role_assignments
  tags                = var.tags
  resource_types      = var.resource_types.network_local_network_gateways
  ignore_body_changes = var.ignore_body_changes.network_local_network_gateways
  retry               = var.retry
  timeouts            = var.timeouts
}

