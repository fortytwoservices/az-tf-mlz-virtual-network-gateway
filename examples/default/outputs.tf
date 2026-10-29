output "bgp_settings" {
  description = "The gateway's ASN and BGP peer addresses, for the on-premises side."
  value       = module.virtual_network_gateway.bgp_settings
}

output "public_ip_addresses" {
  description = "The gateway's public IP addresses, by IP configuration."
  value       = module.virtual_network_gateway.public_ip_addresses
}

output "resource_id" {
  description = "Resource ID of the gateway."
  value       = module.virtual_network_gateway.resource_id
}
