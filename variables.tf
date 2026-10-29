variable "location" {
  type        = string
  description = "Azure region of the gateway, and of the public IP addresses, local network gateways and connections the module creates, for example `swedencentral`."
  nullable    = false
}

variable "name" {
  type        = string
  description = "Name of the virtual network gateway."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9_.-]{0,78}[a-zA-Z0-9_])?$", var.name))
    error_message = "`name` must be 1 to 80 characters: letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }
}

variable "parent_id" {
  type        = string
  description = "Resource ID of the resource group the gateway and everything the module creates are created in. The gateway's IP configuration IDs are built from it, so pass it as Azure returns it (`/subscriptions/<id>/resourceGroups/<name>`)."
  nullable    = false

  validation {
    condition     = can(provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", var.parent_id))
    error_message = "`parent_id` must be a resource group resource ID."
  }
}

variable "subnet_id" {
  type        = string
  description = "Resource ID of the virtual network's `GatewaySubnet`: /27 or larger, /26 or larger for `ErGwScale` (Azure: `GatewaySubnetTooSmallForExpressrouteGatewaySku`; Microsoft Learn, \"Configure a scalable ExpressRoute gateway\"). The subnet belongs to the caller (the hub composition creates it); a VPN gateway and an ExpressRoute gateway can share it. Changing it replaces the gateway."
  nullable    = false

  validation {
    condition     = lower(try(provider::azapi::parse_resource_id("Microsoft.Network/virtualNetworks/subnets", var.subnet_id).name, "")) == "gatewaysubnet"
    error_message = "`subnet_id` must be the resource ID of a subnet named `GatewaySubnet`."
  }
}

variable "active_active" {
  type        = bool
  default     = false
  description = "VPN only: active-active, two gateway instances each with its own public IP address and tunnels, so `ip_configurations` holds two (three with `point_to_site`). Azure switches a gateway either way in place, in about 45 minutes; with BGP, the gateway's BGP peer addresses change (Microsoft Learn, \"Change a VPN gateway mode: active-active\")."
  nullable    = false

  validation {
    condition     = !var.active_active || var.gateway_type == "Vpn"
    error_message = "`active_active` is a VPN gateway setting."
  }
}

variable "bgp" {
  type = object({
    asn         = optional(number, 65515)
    peer_weight = optional(number, 0)
  })
  default     = null
  description = <<DESCRIPTION
(Optional) VPN only: BGP on the gateway. Null turns it off.

- `asn` - (Optional) The gateway's ASN. Defaults to `65515`, Azure's own, which on-premises peers cannot use. ASNs Azure or IANA reserve otherwise are refused (8074, 8075, 12076, 65517 to 65520, 23456, 64496 to 64511, 65535 to 65551); private ASNs are 64512 to 65514 and 65521 to 65534 (Microsoft Learn, VPN Gateway FAQ).
- `peer_weight` - (Optional) Weight added to routes learned from BGP peers, 0 to 100. Defaults to `0`.

Azure assigns the BGP peer addresses from `GatewaySubnet`, one per gateway instance (output `bgp_settings`); custom APIPA addresses are set per IP configuration (`ip_configurations.*.apipa_addresses`).
DESCRIPTION

  validation {
    condition     = var.bgp == null || var.gateway_type == "Vpn"
    error_message = "`bgp` is a VPN gateway setting."
  }
  validation {
    condition = var.bgp == null ? true : (
      floor(var.bgp.asn) == var.bgp.asn && var.bgp.asn >= 1 && var.bgp.asn <= 4294967294 &&
      !contains([8074, 8075, 12076, 65517, 65518, 65519, 65520, 23456], var.bgp.asn) &&
      !(var.bgp.asn >= 64496 && var.bgp.asn <= 64511) && !(var.bgp.asn >= 65535 && var.bgp.asn <= 65551)
    )
    error_message = "`bgp.asn` must be a whole number from 1 to 4294967294 that Azure and IANA do not reserve (65515, Azure's default, is allowed)."
  }
  validation {
    condition     = var.bgp == null ? true : floor(var.bgp.peer_weight) == var.bgp.peer_weight && var.bgp.peer_weight >= 0 && var.bgp.peer_weight <= 100
    error_message = "`bgp.peer_weight` must be a whole number from 0 to 100."
  }
}

variable "express_route_scale_units" {
  type = object({
    min = number
    max = number
  })
  default     = null
  description = "(Optional) `ErGwScale` only, and required for it: the minimum and maximum scale units, 1 to 40 (1 Gbps each). Equal values give a fixed size; a minimum of 2 or more below the maximum turns on autoscaling, and a maximum of 1 needs a minimum of 1 (Microsoft Learn, \"About ExpressRoute scalable gateway\")."

  validation {
    condition     = (var.express_route_scale_units != null) == (var.sku == "ErGwScale")
    error_message = "`express_route_scale_units` is required for `ErGwScale` and taken by no other SKU."
  }
  validation {
    condition = var.express_route_scale_units == null ? true : (
      floor(var.express_route_scale_units.min) == var.express_route_scale_units.min && floor(var.express_route_scale_units.max) == var.express_route_scale_units.max &&
      var.express_route_scale_units.min >= 1 && var.express_route_scale_units.max <= 40 && var.express_route_scale_units.min <= var.express_route_scale_units.max &&
      (var.express_route_scale_units.min == var.express_route_scale_units.max || var.express_route_scale_units.min >= 2)
    )
    error_message = "`express_route_scale_units` must be whole numbers from 1 to 40 with `min` no larger than `max`; autoscaling (`min` below `max`) needs a `min` of 2 or more."
  }
}

variable "gateway_type" {
  type        = string
  default     = "Vpn"
  description = "`Vpn` or `ExpressRoute`. Changing it replaces the gateway."
  nullable    = false

  validation {
    condition     = contains(["Vpn", "ExpressRoute"], var.gateway_type)
    error_message = "`gateway_type` must be `Vpn` or `ExpressRoute`."
  }
}

variable "ip_configurations" {
  type = map(object({
    public_ip = optional(object({
      name                = string
      public_ip_prefix_id = optional(string)
    }))
    public_ip_resource_id = optional(string)
    apipa_addresses       = optional(list(string), [])
  }))
  default     = {}
  description = <<DESCRIPTION
VPN only, and required for it: the gateway's IP configurations, by name, in name order. The first holds instance 0, the second instance 1 of an active-active gateway; one for active-standby, two for active-active, and a third, for point-to-site, when an active-active gateway has `point_to_site`. An ExpressRoute gateway takes none: Azure assigns and manages its public IP address, and the module names its one IP configuration `default`.

- `public_ip` - (Optional) A public IP address the module creates through `az-tf-mlz-public-ip` (Standard, static, its zones left to Azure: zone-redundant where the region has zones): `name`, and optionally `public_ip_prefix_id`.
- `public_ip_resource_id` - (Optional) An existing Standard public IP address with static allocation instead. Exactly one of the two.
- `apipa_addresses` - (Optional) Custom APIPA BGP addresses of this instance, from 169.254.21.0 to 169.254.22.255, for on-premises devices that peer over APIPA addresses. Needs `bgp`; not on the point-to-site IP configuration.

Azure does not change a gateway's first public IP address (Microsoft Learn, "Manage a public IP address with a VPN gateway"), so changing the first IP configuration's name or address replaces the gateway; keep its name first in order. Adding and removing the others (active-standby to active-active and back) updates the gateway in place, and a created address that is removed is deleted only after the gateway has let go of it.
DESCRIPTION
  nullable    = false

  validation {
    condition = length(var.ip_configurations) == (
      var.gateway_type == "ExpressRoute" ? 0 : (var.active_active ? 2 : 1) + (var.active_active && var.point_to_site != null ? 1 : 0)
    )
    error_message = "`ip_configurations` needs one entry for an active-standby VPN gateway, two for active-active, three for active-active with `point_to_site`, and none for ExpressRoute."
  }
  validation {
    condition     = alltrue([for configuration in values(var.ip_configurations) : (configuration.public_ip == null) != (configuration.public_ip_resource_id == null)])
    error_message = "Each of `ip_configurations` needs exactly one of `public_ip` (created) and `public_ip_resource_id` (existing)."
  }
  validation {
    condition     = alltrue([for configuration in values(var.ip_configurations) : configuration.public_ip_resource_id == null ? true : can(provider::azapi::parse_resource_id("Microsoft.Network/publicIPAddresses", configuration.public_ip_resource_id))])
    error_message = "Each `ip_configurations.*.public_ip_resource_id` must be a public IP address resource ID."
  }
  validation {
    condition = alltrue(flatten([for configuration in values(var.ip_configurations) : [
      for address in configuration.apipa_addresses : can(regex("^169\\.254\\.2[12]\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$", address))
    ]]))
    error_message = "Each `ip_configurations.*.apipa_addresses` entry must be an address from 169.254.21.0 to 169.254.22.255."
  }
  validation {
    condition     = var.bgp != null || alltrue([for configuration in values(var.ip_configurations) : length(configuration.apipa_addresses) == 0])
    error_message = "`ip_configurations.*.apipa_addresses` needs `bgp`."
  }
  validation {
    condition     = alltrue([for index, name in sort(keys(var.ip_configurations)) : index < (var.active_active ? 2 : 1) || length(var.ip_configurations[name].apipa_addresses) == 0])
    error_message = "`apipa_addresses` belong to the gateway instances' IP configurations, not to the third (point-to-site) one."
  }
}

variable "point_to_site" {
  type = object({
    address_space = list(string)
    protocols     = optional(list(string), ["OpenVPN"])
    entra_id = optional(object({
      tenant_id = string
      audience  = optional(string, "c632b3df-fb67-4d84-bdcf-b95ad541b5c8")
    }))
    root_certificates    = optional(map(string), {})
    revoked_certificates = optional(map(string), {})
  })
  default     = null
  description = <<DESCRIPTION
(Optional) VPN only: point-to-site (user VPN). Null turns it off.

- `address_space` - Address ranges the VPN clients get addresses from, in CIDR notation; they must not overlap the virtual network or on-premises ranges.
- `protocols` - (Optional) `OpenVPN`, `IkeV2` and/or `SSTP`. Defaults to `["OpenVPN"]`.
- `entra_id` - (Optional) Microsoft Entra ID authentication in Azure's public cloud (OpenVPN only, with the Azure VPN Client): `tenant_id`, and `audience`, which defaults to the Microsoft-registered Azure VPN Client (`c632b3df-fb67-4d84-bdcf-b95ad541b5c8`; Microsoft Learn, "Configure P2S VPN Gateway for Microsoft Entra ID authentication").
- `root_certificates` - (Optional) Certificate authentication: trusted root certificates, by name, as their Base64 public data (without the BEGIN and END lines).
- `revoked_certificates` - (Optional) Revoked client certificates, by name, as their thumbprints.

At least one of `entra_id` and `root_certificates`. An active-active gateway needs a third IP configuration for point-to-site.
DESCRIPTION

  validation {
    condition     = var.point_to_site == null || var.gateway_type == "Vpn"
    error_message = "`point_to_site` is a VPN gateway setting."
  }
  validation {
    condition     = var.point_to_site == null ? true : length(var.point_to_site.address_space) > 0 && alltrue([for prefix in var.point_to_site.address_space : can(cidrnetmask(prefix))])
    error_message = "`point_to_site.address_space` needs one or more IPv4 ranges in CIDR notation."
  }
  validation {
    condition     = var.point_to_site == null ? true : length(var.point_to_site.protocols) > 0 && length(distinct(var.point_to_site.protocols)) == length(var.point_to_site.protocols) && alltrue([for protocol in var.point_to_site.protocols : contains(["OpenVPN", "IkeV2", "SSTP"], protocol)])
    error_message = "`point_to_site.protocols` needs one or more of `OpenVPN`, `IkeV2` and `SSTP`, each once."
  }
  validation {
    condition     = var.point_to_site == null ? true : var.point_to_site.entra_id != null || length(var.point_to_site.root_certificates) > 0
    error_message = "`point_to_site` needs `entra_id`, `root_certificates` or both."
  }
  validation {
    condition     = var.point_to_site == null ? true : var.point_to_site.entra_id == null || contains(var.point_to_site.protocols, "OpenVPN")
    error_message = "Microsoft Entra ID authentication needs the `OpenVPN` protocol."
  }
}

variable "sku" {
  type        = string
  default     = "VpnGw1AZ"
  description = "Gateway SKU. VPN: `VpnGw1AZ` to `VpnGw5AZ` (Microsoft Learn, \"VPN Gateway SKU consolidation and migration\": no new non-AZ gateways since 2025-11-01; `Basic` lacks BGP and active-active and is not for production). ExpressRoute: `ErGw1AZ`, `ErGw2AZ`, `ErGw3AZ` or `ErGwScale` (with `express_route_scale_units`, in a `GatewaySubnet` of /26 or larger). Azure resizes a gateway in place within its family and generation; it does not downgrade an ExpressRoute gateway."
  nullable    = false

  validation {
    condition     = contains(var.gateway_type == "Vpn" ? ["VpnGw1AZ", "VpnGw2AZ", "VpnGw3AZ", "VpnGw4AZ", "VpnGw5AZ"] : ["ErGw1AZ", "ErGw2AZ", "ErGw3AZ", "ErGwScale"], var.sku)
    error_message = "`sku` must be `VpnGw1AZ` to `VpnGw5AZ` for a VPN gateway, or `ErGw1AZ`, `ErGw2AZ`, `ErGw3AZ` or `ErGwScale` for ExpressRoute."
  }
}


variable "vpn_generation" {
  type        = string
  default     = null
  description = "(Optional) VPN only: `Generation1` or `Generation2`. Defaults to the SKU's: `Generation1` for `VpnGw1AZ` (it has no other), `Generation2` for the others (`VpnGw2AZ` and `VpnGw3AZ` come in both; Microsoft Learn, \"About gateway SKUs\"). Changing it replaces the gateway, so set `Generation1` to resize a `VpnGw1AZ` gateway in place to `VpnGw2AZ` or `VpnGw3AZ`."

  validation {
    condition     = var.vpn_generation == null || var.gateway_type == "Vpn"
    error_message = "`vpn_generation` is a VPN gateway setting."
  }
  validation {
    condition = var.vpn_generation == null ? true : (
      var.vpn_generation == "Generation1" ? contains(["VpnGw1AZ", "VpnGw2AZ", "VpnGw3AZ"], var.sku) :
      var.vpn_generation == "Generation2" ? contains(["VpnGw2AZ", "VpnGw3AZ", "VpnGw4AZ", "VpnGw5AZ"], var.sku) : false
    )
    error_message = "`vpn_generation` must be `Generation1` (`VpnGw1AZ` to `VpnGw3AZ`) or `Generation2` (`VpnGw2AZ` to `VpnGw5AZ`)."
  }
}
