resource "azapi_resource" "this" {
  type      = var.resource_types.network_virtual_network_gateways
  name      = var.name
  parent_id = var.parent_id
  location  = var.location
  body = {
    properties = merge(
      {
        gatewayType          = var.gateway_type
        sku                  = { name = var.sku, tier = var.sku }
        vpnGatewayGeneration = local.vpn_generation
        ipConfigurations = [for name in local.ip_configuration_names : {
          name = name
          properties = merge(
            { privateIPAllocationMethod = "Dynamic", subnet = { id = var.subnet_id } },
            # merge() skips null, which unlike {} unifies with either object type. An ExpressRoute
            # gateway's public IP address is assigned and managed by Azure (Microsoft Learn, "About
            # ExpressRoute virtual network gateways").
            local.vpn ? { publicIPAddress = { id = local.public_ip_ids[name] } } : null,
          )
        }]
      },
      local.vpn ? {
        vpnType      = "RouteBased"
        activeActive = var.active_active
        enableBgp    = var.bgp != null
        # Always sent: Azure reports BGP settings on every VPN gateway, its own ASN 65515 when BGP is off,
        # and azapi compares a null with what Azure reports. One entry per gateway instance, also without
        # custom addresses: Azure reports one each, and an empty list would differ on every plan
        # (Azure/terraform-azurerm-avm-ptn-alz-connectivity-hub-and-spoke-vnet#151).
        bgpSettings = {
          asn        = var.bgp == null ? 65515 : var.bgp.asn
          peerWeight = var.bgp == null ? 0 : var.bgp.peer_weight
          bgpPeeringAddresses = [for index, name in local.ip_configuration_names : {
            ipconfigurationId    = local.ip_configuration_ids[name]
            customBgpIpAddresses = var.ip_configurations[name].apipa_addresses
          } if index < (var.active_active ? 2 : 1)]
        }
        vpnClientConfiguration = var.point_to_site == null ? null : {
          vpnClientAddressPool   = { addressPrefixes = var.point_to_site.address_space }
          vpnClientProtocols     = var.point_to_site.protocols
          vpnAuthenticationTypes = concat(var.point_to_site.entra_id == null ? [] : ["AAD"], length(var.point_to_site.root_certificates) == 0 ? [] : ["Certificate"])
          aadTenant              = var.point_to_site.entra_id == null ? null : "https://login.microsoftonline.com/${var.point_to_site.entra_id.tenant_id}"
          aadIssuer              = var.point_to_site.entra_id == null ? null : "https://sts.windows.net/${var.point_to_site.entra_id.tenant_id}/"
          aadAudience            = var.point_to_site.entra_id == null ? null : var.point_to_site.entra_id.audience
          vpnClientRootCertificates = [for name, data in var.point_to_site.root_certificates : {
            name       = name
            properties = { publicCertData = data }
          }]
          vpnClientRevokedCertificates = [for name, thumbprint in var.point_to_site.revoked_certificates : {
            name       = name
            properties = { thumbprint = thumbprint }
          }]
        }
      } : null,
      var.express_route_scale_units == null ? null : {
        autoScaleConfiguration = { bounds = { min = var.express_route_scale_units.min, max = var.express_route_scale_units.max } }
      },
    )
  }
  ignore_body_changes = length(var.ignore_body_changes.network_virtual_network_gateways) > 0 ? var.ignore_body_changes.network_virtual_network_gateways : null
  # Azure may report a peering address entry for an IP configuration the body does not list (the
  # point-to-site one); the entries are matched by IP configuration, the certificates by name.
  ignore_other_items_in_list = ["properties.bgpSettings.bgpPeeringAddresses"]
  list_unique_id_property = {
    "properties.bgpSettings.bgpPeeringAddresses"                     = "ipconfigurationId"
    "properties.vpnClientConfiguration.vpnClientRootCertificates"    = "name"
    "properties.vpnClientConfiguration.vpnClientRevokedCertificates" = "name"
  }
  replace_triggers_external_values = local.gateway_replace_triggers
  response_export_values           = ["properties.bgpSettings"]
  retry                            = var.retry
  tags                             = var.tags

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }
}
