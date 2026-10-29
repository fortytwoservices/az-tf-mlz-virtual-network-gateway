variable "connection_secrets" {
  type        = map(string)
  default     = {}
  ephemeral   = true
  sensitive   = true
  description = "The connections' keys, by `connections` key: the pre-shared key of an `IPsec` or `Vnet2Vnet` connection (required), the authorization key of an `ExpressRoute` connection to a circuit in another subscription (optional). Ephemeral and write-only: sent to Azure, never stored in state; change the connection's `secret_version` to send a new key."
  nullable    = false
}

variable "connections" {
  type = map(object({
    name                               = string
    type                               = optional(string, "IPsec")
    local_network_gateway_key          = optional(string)
    local_network_gateway_id           = optional(string)
    peer_virtual_network_gateway_id    = optional(string)
    express_route_circuit_id           = optional(string)
    enable_bgp                         = optional(bool, false)
    connection_protocol                = optional(string, "IKEv2")
    connection_mode                    = optional(string, "Default")
    dpd_timeout_seconds                = optional(number, 45)
    routing_weight                     = optional(number, 0)
    use_policy_based_traffic_selectors = optional(bool, false)
    ipsec_policy = optional(object({
      dh_group               = string
      ike_encryption         = string
      ike_integrity          = string
      ipsec_encryption       = string
      ipsec_integrity        = string
      pfs_group              = string
      sa_data_size_kilobytes = optional(number, 102400000)
      sa_lifetime_seconds    = optional(number, 27000)
    }))
    express_route_gateway_bypass = optional(bool, false)
    custom_bgp_addresses         = optional(map(string), {})
    secret_version               = optional(string, "1")
    lock = optional(object({
      kind  = string
      name  = optional(string, null)
      notes = optional(string, null)
    }))
    role_assignments = optional(map(object({
      name                                   = optional(string, null)
      role_definition_id_or_name             = string
      principal_id                           = string
      description                            = optional(string, null)
      skip_service_principal_aad_check       = optional(bool, false)
      condition                              = optional(string, null)
      condition_version                      = optional(string, null)
      delegated_managed_identity_resource_id = optional(string, null)
      principal_type                         = optional(string, null)
    })), {})
    diagnostic_settings = optional(map(object({
      name = optional(string, null)
      metrics = optional(set(object({
        category = optional(string, null)
        enabled  = optional(bool, true)
        retention_policy = optional(object({
          days    = optional(number, 0)
          enabled = optional(bool, false)
        }), {})
      })), [])
      log_analytics_destination_type           = optional(string, "Dedicated")
      workspace_resource_id                    = optional(string, null)
      storage_account_resource_id              = optional(string, null)
      event_hub_authorization_rule_resource_id = optional(string, null)
      event_hub_name                           = optional(string, null)
      marketplace_partner_resource_id          = optional(string, null)
    })), {})
  }))
  default     = {}
  description = <<DESCRIPTION
Connections of the gateway, by a stable key, created through `modules/connection` (its README describes every field). Their keys go in `connection_secrets` under the same key. A replaced gateway keeps its resource ID, so its connections are replaced with it; a connection is also replaced when its site changes.

- `name` - Name of the connection.
- `type` - (Optional) `IPsec` (default), `Vnet2Vnet` or `ExpressRoute`.
- `local_network_gateway_key` or `local_network_gateway_id` - IPsec: a key of `local_network_gateways`, or an existing local network gateway's ID.
- `peer_virtual_network_gateway_id` - Vnet2Vnet: the other gateway's ID.
- `express_route_circuit_id` - ExpressRoute: the circuit's ID.
- `custom_bgp_addresses` - (Optional) IPsec: the custom APIPA BGP address to use, by IP configuration name of this gateway (one of that configuration's `apipa_addresses`).
- `enable_bgp`, `connection_protocol`, `connection_mode`, `dpd_timeout_seconds`, `routing_weight`, `use_policy_based_traffic_selectors`, `ipsec_policy`, `express_route_gateway_bypass`, `secret_version` - (Optional) As in `modules/connection`.
- `lock`, `role_assignments`, `diagnostic_settings` - (Optional) On the connection, as the module's own; diagnostic settings take `metrics` only (`AllMetrics`), a connection having no log categories.
DESCRIPTION
  nullable    = false

  validation {
    condition = alltrue([for connection in values(var.connections) :
      connection.type != "IPsec" ? connection.local_network_gateway_key == null && connection.local_network_gateway_id == null :
      (connection.local_network_gateway_key == null) != (connection.local_network_gateway_id == null)
    ])
    error_message = "An IPsec connection needs exactly one of `local_network_gateway_key` and `local_network_gateway_id`; other types take neither."
  }
  validation {
    condition     = alltrue([for connection in values(var.connections) : connection.local_network_gateway_key == null ? true : contains(keys(var.local_network_gateways), connection.local_network_gateway_key)])
    error_message = "Each `connections.*.local_network_gateway_key` must be a key of `local_network_gateways`."
  }
  validation {
    condition     = alltrue([for connection in values(var.connections) : alltrue([for name, address in connection.custom_bgp_addresses : contains(try(var.ip_configurations[name].apipa_addresses, []), address)])])
    error_message = "Each `connections.*.custom_bgp_addresses` entry must map a name of `ip_configurations` to one of that configuration's `apipa_addresses`."
  }
  validation {
    condition     = alltrue([for connection in values(var.connections) : (connection.type == "ExpressRoute") == (var.gateway_type == "ExpressRoute")])
    error_message = "An ExpressRoute gateway takes `ExpressRoute` connections only, and a VPN gateway `IPsec` and `Vnet2Vnet` connections only."
  }
}

variable "local_network_gateways" {
  type = map(object({
    name               = string
    gateway_ip_address = optional(string)
    fqdn               = optional(string)
    address_prefixes   = optional(list(string), [])
    bgp = optional(object({
      asn                 = number
      bgp_peering_address = string
      peer_weight         = optional(number, 0)
    }))
    lock = optional(object({
      kind  = string
      name  = optional(string, null)
      notes = optional(string, null)
    }))
    role_assignments = optional(map(object({
      name                                   = optional(string, null)
      role_definition_id_or_name             = string
      principal_id                           = string
      description                            = optional(string, null)
      skip_service_principal_aad_check       = optional(bool, false)
      condition                              = optional(string, null)
      condition_version                      = optional(string, null)
      delegated_managed_identity_resource_id = optional(string, null)
      principal_type                         = optional(string, null)
    })), {})
  }))
  default     = {}
  description = <<DESCRIPTION
On-premises sites, by a stable key, created through `modules/local_network_gateway` (its README describes every field); `connections` refer to them by key. Azure does not move a connection to another site, so a renamed site replaces its connections.

- `name` - Name of the local network gateway.
- `gateway_ip_address` or `fqdn` - The on-premises VPN device's public IP address or FQDN, exactly one.
- `address_prefixes` - (Optional) On-premises address ranges; may be empty with `bgp`, not without.
- `bgp` - (Optional) The device's `asn`, `bgp_peering_address` and `peer_weight`.
- `lock`, `role_assignments` - (Optional) On the local network gateway, as the module's own `lock` and `role_assignments`.
DESCRIPTION
  nullable    = false
}
