variable "location" {
  type        = string
  description = "Azure region of the local network gateway, for example `swedencentral`."
  nullable    = false
}

variable "name" {
  type        = string
  description = "Name of the local network gateway."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9_.-]{0,78}[a-zA-Z0-9_])?$", var.name))
    error_message = "`name` must be 1 to 80 characters: letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }
}

variable "parent_id" {
  type        = string
  description = "Resource ID of the resource group the local network gateway is created in."
  nullable    = false

  validation {
    condition     = can(provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", var.parent_id))
    error_message = "`parent_id` must be a resource group resource ID."
  }
}

variable "address_prefixes" {
  type        = list(string)
  default     = []
  description = "IPv4 address ranges of the on-premises network, in CIDR notation. May be empty with `bgp`: Azure then learns the routes from the peer and adds the peer's BGP address itself. Without `bgp` at least one is required (Azure: `LocalNetworkGatewayCannotHaveEmptyAddressPrefixAndBgpSettings`)."
  nullable    = false

  validation {
    condition     = alltrue([for prefix in var.address_prefixes : can(cidrnetmask(prefix))])
    error_message = "Each of `address_prefixes` must be an IPv4 range in CIDR notation."
  }
  validation {
    condition     = length(var.address_prefixes) > 0 || var.bgp != null
    error_message = "A local network gateway needs `address_prefixes`, `bgp` or both."
  }
}

variable "bgp" {
  type = object({
    asn                 = number
    bgp_peering_address = string
    peer_weight         = optional(number, 0)
  })
  default     = null
  description = <<DESCRIPTION
(Optional) BGP settings of the on-premises VPN device.

- `asn` - The device's ASN. It must differ from the Azure gateway's, and ASNs Azure or IANA reserve are refused (8074, 8075, 12076, 65515, 65517 to 65520, 23456, 64496 to 64511, 65535 to 65551; Microsoft Learn, VPN Gateway FAQ).
- `bgp_peering_address` - The device's BGP peer IPv4 address, which cannot be its public IP address; an APIPA address (169.254.0.0/16) pairs with a custom APIPA address on the Azure gateway.
- `peer_weight` - (Optional) Weight added to routes learned from this peer, 0 to 100. Defaults to `0`.
DESCRIPTION

  validation {
    condition = var.bgp == null ? true : (
      floor(var.bgp.asn) == var.bgp.asn && var.bgp.asn >= 1 && var.bgp.asn <= 4294967294 &&
      !contains([8074, 8075, 12076, 65515, 65517, 65518, 65519, 65520, 23456], var.bgp.asn) &&
      !(var.bgp.asn >= 64496 && var.bgp.asn <= 64511) && !(var.bgp.asn >= 65535 && var.bgp.asn <= 65551)
    )
    error_message = "`bgp.asn` must be a whole number from 1 to 4294967294 that Azure and IANA do not reserve."
  }
  validation {
    condition     = var.bgp == null ? true : can(cidrnetmask("${var.bgp.bgp_peering_address}/32"))
    error_message = "`bgp.bgp_peering_address` must be an IPv4 address."
  }
  validation {
    condition     = var.bgp == null ? true : floor(var.bgp.peer_weight) == var.bgp.peer_weight && var.bgp.peer_weight >= 0 && var.bgp.peer_weight <= 100
    error_message = "`bgp.peer_weight` must be a whole number from 0 to 100."
  }
}

variable "fqdn" {
  type        = string
  default     = null
  description = "(Optional) FQDN of the on-premises VPN device; exactly one of `fqdn` and `gateway_ip_address`. Switching between them updates the local network gateway in place."
}

variable "gateway_ip_address" {
  type        = string
  default     = null
  description = "(Optional) Public IPv4 address of the on-premises VPN device; exactly one of `gateway_ip_address` and `fqdn`."

  validation {
    condition     = (var.gateway_ip_address == null) != (var.fqdn == null)
    error_message = "Set exactly one of `gateway_ip_address` and `fqdn`."
  }
  validation {
    condition     = var.gateway_ip_address == null ? true : can(cidrnetmask("${var.gateway_ip_address}/32"))
    error_message = "`gateway_ip_address` must be an IPv4 address."
  }
}

variable "tags" {
  type        = map(string)
  default     = null
  description = "(Optional) Tags of the resource."
}
