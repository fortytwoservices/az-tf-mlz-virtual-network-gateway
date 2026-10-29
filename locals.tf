locals {
  vpn = var.gateway_type == "Vpn"
  # In name order: Azure takes the first as instance 0 and the second as instance 1 of an active-active
  # gateway. An ExpressRoute gateway has one, without a public IP address.
  ip_configuration_names = local.vpn ? sort(keys(var.ip_configurations)) : ["default"]
  # Built rather than read, so they are known before the gateway exists: the gateway's own BGP settings
  # and its connections' custom BGP addresses refer to them.
  ip_configuration_ids = { for name in local.ip_configuration_names : name => "${var.parent_id}/providers/Microsoft.Network/virtualNetworkGateways/${var.name}/ipConfigurations/${name}" }
  # The public IP addresses the module creates, by IP configuration. Only the presence of an object
  # decides membership, so a name unknown until apply cannot make the keys unknown.
  created_public_ips = { for name, configuration in var.ip_configurations : name => configuration.public_ip if configuration.public_ip != null }
  # Every public IP address, created or existing, by IP configuration.
  public_ip_ids = merge(
    { for name, public_ip in module.public_ip : name => public_ip.resource_id },
    { for name, configuration in var.ip_configurations : name => configuration.public_ip_resource_id if configuration.public_ip_resource_id != null },
  )
  vpn_generation = local.vpn ? coalesce(var.vpn_generation, var.sku == "VpnGw1AZ" ? "Generation1" : "Generation2") : "None"
  # What Azure changes only by creating the gateway again: its type, its virtual network, its generation
  # (azurerm marks it ForceNew) and its first public IP address (Microsoft Learn, "Manage a public IP
  # address with a VPN gateway"). Compared as inputs, so Azure's casing of IDs cannot replace anything.
  # Also the connections' replacement triggers: a replaced gateway keeps its resource ID, so its
  # connections are replaced with it, deleted before the old gateway and created after the new one.
  # The keys are part of the contract: a new key would replace every deployed gateway.
  gateway_replace_triggers = {
    gateway_type = var.gateway_type
    generation   = local.vpn_generation
    ip_configuration = local.first_ip_configuration == null ? null : {
      name      = local.ip_configuration_names[0]
      public_ip = local.first_ip_configuration.public_ip != null ? jsonencode(local.first_ip_configuration.public_ip) : try(lower(local.first_ip_configuration.public_ip_resource_id), null)
    }
    subnet_id = lower(var.subnet_id)
  }
  # Null for an ExpressRoute gateway, and while validation reports a VPN gateway without any.
  first_ip_configuration = local.vpn ? try(var.ip_configurations[local.ip_configuration_names[0]], null) : null
}
