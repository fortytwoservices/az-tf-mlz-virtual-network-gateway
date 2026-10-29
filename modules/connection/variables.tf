variable "location" {
  type        = string
  description = "Azure region of the connection, the virtual network gateway's region, for example `swedencentral`."
  nullable    = false
}

variable "name" {
  type        = string
  description = "Name of the connection."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9_.-]{0,78}[a-zA-Z0-9_])?$", var.name))
    error_message = "`name` must be 1 to 80 characters: letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }
}

variable "parent_id" {
  type        = string
  description = "Resource ID of the resource group the connection is created in."
  nullable    = false

  validation {
    condition     = can(provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", var.parent_id))
    error_message = "`parent_id` must be a resource group resource ID."
  }
}

variable "virtual_network_gateway_id" {
  type        = string
  description = "Resource ID of the Azure virtual network gateway the connection belongs to. Connections to one gateway are written one at a time. Changing it replaces the connection."
  nullable    = false

  validation {
    condition     = can(provider::azapi::parse_resource_id("Microsoft.Network/virtualNetworkGateways", var.virtual_network_gateway_id))
    error_message = "`virtual_network_gateway_id` must be a virtual network gateway resource ID."
  }
}

variable "authorization_key" {
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
  description = "(Optional) Authorization key of an ExpressRoute circuit in another subscription. Write-only: it is sent to Azure but never stored in state; change `secret_version` to send a new one."

  validation {
    condition     = var.authorization_key == null || var.type == "ExpressRoute"
    error_message = "`authorization_key` is taken only by ExpressRoute connections."
  }
}

variable "connection_mode" {
  type        = string
  default     = "Default"
  description = "IPsec only: whether the Azure gateway initiates and responds (`Default`), only initiates (`InitiatorOnly`) or only responds (`ResponderOnly`). Changing it replaces the connection (azurerm marks it ForceNew)."
  nullable    = false

  validation {
    condition     = contains(["Default", "InitiatorOnly", "ResponderOnly"], var.connection_mode)
    error_message = "`connection_mode` must be `Default`, `InitiatorOnly` or `ResponderOnly`."
  }
}

variable "connection_protocol" {
  type        = string
  default     = "IKEv2"
  description = "IPsec and Vnet2Vnet: the IKE protocol, `IKEv2` or `IKEv1`. Changing it replaces the connection (azurerm marks it ForceNew)."
  nullable    = false

  validation {
    condition     = contains(["IKEv2", "IKEv1"], var.connection_protocol)
    error_message = "`connection_protocol` must be `IKEv2` or `IKEv1`."
  }
}

variable "custom_bgp_addresses" {
  type = list(object({
    ip_configuration_id = string
    address             = string
  }))
  default     = []
  description = <<DESCRIPTION
IPsec only: the custom APIPA BGP address the Azure gateway uses for this connection, per gateway IP configuration (one per instance of an active-active gateway). Each address must be one of the gateway's own custom APIPA addresses.

- `ip_configuration_id` - Resource ID of the gateway's IP configuration (`<gateway ID>/ipConfigurations/<name>`).
- `address` - The APIPA address, from 169.254.21.0 to 169.254.22.255.
DESCRIPTION
  nullable    = false

  validation {
    condition     = length(var.custom_bgp_addresses) == 0 || var.type == "IPsec"
    error_message = "`custom_bgp_addresses` are taken only by IPsec connections."
  }
  validation {
    condition     = alltrue([for address in var.custom_bgp_addresses : can(regex("^169\\.254\\.2[12]\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$", address.address))])
    error_message = "Each `custom_bgp_addresses.*.address` must be an address from 169.254.21.0 to 169.254.22.255."
  }
  validation {
    condition     = alltrue([for address in var.custom_bgp_addresses : can(provider::azapi::parse_resource_id("Microsoft.Network/virtualNetworkGateways/ipConfigurations", address.ip_configuration_id))])
    error_message = "Each `custom_bgp_addresses.*.ip_configuration_id` must be a gateway IP configuration ID (`<gateway ID>/ipConfigurations/<name>`)."
  }
}

variable "dpd_timeout_seconds" {
  type        = number
  default     = 45
  description = "IPsec only: dead peer detection timeout in seconds, 9 to 3600. Defaults to `45`, Azure's default. Changing it replaces the connection (azurerm marks it ForceNew)."
  nullable    = false

  validation {
    condition     = var.dpd_timeout_seconds >= 9 && var.dpd_timeout_seconds <= 3600 && floor(var.dpd_timeout_seconds) == var.dpd_timeout_seconds
    error_message = "`dpd_timeout_seconds` must be a whole number from 9 to 3600."
  }
}

variable "enable_bgp" {
  type        = bool
  default     = false
  description = "IPsec and Vnet2Vnet: exchange routes with BGP. Both gateways (or the gateway and the local network gateway) need BGP settings."
  nullable    = false
}

variable "express_route_circuit_id" {
  type        = string
  default     = null
  description = "(Optional) ExpressRoute only: resource ID of the ExpressRoute circuit (its private peering must exist)."

  validation {
    condition     = var.express_route_circuit_id == null ? true : can(provider::azapi::parse_resource_id("Microsoft.Network/expressRouteCircuits", var.express_route_circuit_id))
    error_message = "`express_route_circuit_id` must be an ExpressRoute circuit resource ID."
  }
}

variable "express_route_gateway_bypass" {
  type        = bool
  default     = false
  description = "ExpressRoute only: FastPath, which sends traffic past the gateway straight to the virtual machines. Needs `ErGw3AZ` or `ErGwScale` with enough scale units (Microsoft Learn, \"About ExpressRoute FastPath\")."
  nullable    = false
}

variable "ipsec_policy" {
  type = object({
    dh_group               = string
    ike_encryption         = string
    ike_integrity          = string
    ipsec_encryption       = string
    ipsec_integrity        = string
    pfs_group              = string
    sa_data_size_kilobytes = optional(number, 102400000)
    sa_lifetime_seconds    = optional(number, 27000)
  })
  default     = null
  description = <<DESCRIPTION
(Optional) IPsec and Vnet2Vnet: a custom IPsec/IKE policy instead of Azure's default proposals. Values as in the ARM schema, for example `dh_group = "DHGroup14"`, `ike_encryption = "AES256"`, `ike_integrity = "SHA256"`, `ipsec_encryption = "GCMAES256"`, `ipsec_integrity = "GCMAES256"`, `pfs_group = "PFS2048"`.

- `sa_data_size_kilobytes` - (Optional) Quick-mode SA payload size in KB. Defaults to `102400000`.
- `sa_lifetime_seconds` - (Optional) Quick-mode SA lifetime in seconds. Defaults to `27000`.
DESCRIPTION
}

variable "local_network_gateway_id" {
  type        = string
  default     = null
  description = "(Optional) IPsec only: resource ID of the local network gateway (the on-premises site). Changing it replaces the connection: Azure does not move a connection to another site (`GatewayConnectionEndpointCannotBeChanged`)."

  validation {
    condition     = var.local_network_gateway_id == null ? true : can(provider::azapi::parse_resource_id("Microsoft.Network/localNetworkGateways", var.local_network_gateway_id))
    error_message = "`local_network_gateway_id` must be a local network gateway resource ID."
  }
}

variable "peer_virtual_network_gateway_id" {
  type        = string
  default     = null
  description = "(Optional) Vnet2Vnet only: resource ID of the other Azure virtual network gateway. Each side needs its own connection, with the same shared key."

  validation {
    condition     = var.peer_virtual_network_gateway_id == null ? true : can(provider::azapi::parse_resource_id("Microsoft.Network/virtualNetworkGateways", var.peer_virtual_network_gateway_id))
    error_message = "`peer_virtual_network_gateway_id` must be a virtual network gateway resource ID."
  }
}

variable "replace_triggers" {
  type        = any
  default     = null
  description = "(Optional) Values whose change replaces the connection, for example the gateway's own replacement triggers: a replaced gateway keeps its resource ID, and Azure deletes no gateway that still has connections. The root module passes the gateway's."
}

variable "routing_weight" {
  type        = number
  default     = 0
  description = "Routing weight of the connection, 0 to 32000. Defaults to `0`."
  nullable    = false

  validation {
    condition     = floor(var.routing_weight) == var.routing_weight && var.routing_weight >= 0 && var.routing_weight <= 32000
    error_message = "`routing_weight` must be a whole number from 0 to 32000."
  }
}

variable "secret_version" {
  type        = string
  default     = "1"
  description = "Version of `shared_key` and `authorization_key`. They are write-only, so Terraform cannot see when they change: change this value to send them to Azure again, for example after rotating the key."
  nullable    = false
}

variable "shared_key" {
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
  description = "(Optional) IPsec and Vnet2Vnet: the pre-shared key, required for those types. Write-only: it is sent to Azure but never stored in state; change `secret_version` to send a new one."

  validation {
    condition     = var.type == "ExpressRoute" ? var.shared_key == null : var.shared_key != null
    error_message = "`shared_key` is required for IPsec and Vnet2Vnet connections, and not taken by ExpressRoute."
  }
}


variable "type" {
  type        = string
  default     = "IPsec"
  description = "Connection type: `IPsec` (site-to-site, to `local_network_gateway_id`), `Vnet2Vnet` (to `peer_virtual_network_gateway_id`) or `ExpressRoute` (to `express_route_circuit_id`). Changing it replaces the connection."
  nullable    = false

  validation {
    condition     = contains(["IPsec", "Vnet2Vnet", "ExpressRoute"], var.type)
    error_message = "`type` must be `IPsec`, `Vnet2Vnet` or `ExpressRoute`."
  }
  validation {
    condition = (
      (var.local_network_gateway_id != null) == (var.type == "IPsec") &&
      (var.peer_virtual_network_gateway_id != null) == (var.type == "Vnet2Vnet") &&
      (var.express_route_circuit_id != null) == (var.type == "ExpressRoute")
    )
    error_message = "Set exactly the peer of the connection type: `local_network_gateway_id` for IPsec, `peer_virtual_network_gateway_id` for Vnet2Vnet, `express_route_circuit_id` for ExpressRoute."
  }
}

variable "use_policy_based_traffic_selectors" {
  type        = bool
  default     = false
  description = "IPsec only: policy-based traffic selectors, for an on-premises policy-based VPN device. Needs `ipsec_policy`."
  nullable    = false

  validation {
    condition     = !var.use_policy_based_traffic_selectors || var.ipsec_policy != null
    error_message = "`use_policy_based_traffic_selectors` needs `ipsec_policy`."
  }
}
