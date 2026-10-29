output "name" {
  description = "Name of the connection."
  value       = azapi_resource.this.name
}

output "resource_id" {
  description = "Resource ID of the connection."
  value       = azapi_resource.this.id
}
