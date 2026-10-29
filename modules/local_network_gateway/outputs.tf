output "name" {
  description = "Name of the local network gateway."
  value       = azapi_resource.this.name
}

output "resource_id" {
  description = "Resource ID of the local network gateway."
  value       = azapi_resource.this.id
}
