output "bgp_settings" {
  description = <<DESCRIPTION
The gateway's BGP settings as Azure reports them, for the on-premises side; null if Azure reports none.

- `asn` - The gateway's ASN.
- `peering_addresses` - By IP configuration name: `default` (the addresses Azure assigns from `GatewaySubnet`), `custom` (the APIPA addresses set) and `tunnel` (the instance's public IP addresses).
DESCRIPTION
  value = try({
    asn = azapi_resource.this.output.properties.bgpSettings.asn
    peering_addresses = { for address in azapi_resource.this.output.properties.bgpSettings.bgpPeeringAddresses : reverse(split("/", address.ipconfigurationId))[0] => {
      default = try(address.defaultBgpIpAddresses, [])
      custom  = try(address.customBgpIpAddresses, [])
      tunnel  = try(address.tunnelIpAddresses, [])
    } }
  }, null)
}

output "connection_resource_ids" {
  description = "Resource IDs of the connections, by `connections` key."
  value       = { for key, connection in module.connection : key => connection.resource_id }
}

output "ip_configuration_ids" {
  description = "Resource IDs of the gateway's IP configurations, by name: for a connection's custom BGP addresses set outside this module."
  value       = local.ip_configuration_ids
}

output "local_network_gateway_resource_ids" {
  description = "Resource IDs of the local network gateways, by `local_network_gateways` key."
  value       = { for key, local_network_gateway in module.local_network_gateway : key => local_network_gateway.resource_id }
}

output "name" {
  description = "Name of the virtual network gateway."
  value       = azapi_resource.this.name
}

output "public_ip_address_ids" {
  description = "Resource IDs of the gateway's public IP addresses, created or given, by IP configuration name; empty for an ExpressRoute gateway, whose address Azure manages."
  value       = local.public_ip_ids
}

output "public_ip_addresses" {
  description = "IP addresses of the public IP addresses the module creates, by IP configuration name."
  value       = { for name, public_ip in module.public_ip : name => public_ip.ip_address }
}

output "resource_id" {
  description = "Resource ID of the virtual network gateway."
  value       = azapi_resource.this.id
}
