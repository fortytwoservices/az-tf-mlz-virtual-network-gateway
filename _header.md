# az-tf-mlz-virtual-network-gateway

A Fortytwo managed landing zone (MLZ) module for a hub virtual network's gateway, in AzAPI: the VPN or
ExpressRoute gateway (`Microsoft.Network/virtualNetworkGateways`), its public IP addresses, and its
on-premises sites (`localNetworkGateways`) and connections (`connections`). Virtual WAN gateways are other
resource types, owned by `az-tf-mlz-connectivity-vwan`.

- **VPN** (`gateway_type = "Vpn"`, default): `VpnGw1AZ` (default) to `VpnGw5AZ`, the SKUs Azure still
  creates; the generation follows the SKU unless set. Active-standby or active-active (switched in place),
  BGP with custom APIPA addresses, and point-to-site with Microsoft Entra ID and/or certificates.
- **ExpressRoute** (`gateway_type = "ExpressRoute"`): `ErGw1AZ` to `ErGw3AZ`, or `ErGwScale` with its
  scale units. Azure assigns and manages its public IP address.
- **Public IP addresses** per IP configuration, created through
  [`az-tf-mlz-public-ip`](https://github.com/fortytwoservices/az-tf-mlz-public-ip) or given by ID. A
  created address that is removed (active-active to active-standby) is deleted only after the gateway has
  let go of it, in one apply.
- **Local network gateways and connections** through `modules/local_network_gateway` and
  `modules/connection`, which can also be called alone (for example from a state that holds a site's
  connections). Connections are `IPsec`, `Vnet2Vnet` or `ExpressRoute`; their keys are ephemeral and
  write-only (`connection_secrets`), sent again when `secret_version` changes. A replaced gateway
  replaces its connections, and so does a changed site (Azure does not move a connection).
- **Every setting is sent**, off or empty when unset, so removing one reaches Azure. BGP settings always
  carry one peering address entry per gateway instance, which keeps plans clean.
- **Replacement:** changing the type, the subnet, the generation or the first IP configuration (Azure
  does not change a gateway's first public IP address) replaces the gateway. A virtual network holds one
  VPN gateway, so the old one is deleted first.
- Lock, role assignments and diagnostic settings, as in Azure Verified Modules, through
  [`az-tf-mlz-interfaces`](https://github.com/fortytwoservices/az-tf-mlz-interfaces), on the gateway (its
  five log categories and metrics), each local network gateway (no diagnostic settings: Azure refuses
  them) and each connection (metrics only). A `ReadOnly` lock blocks updates of the locked resource
  itself; remove it before changing the gateway.
- Creating, changing or deleting a gateway takes up to 45 minutes, so `timeouts` default to 90 minutes.

```hcl
module "virtual_network_gateway" {
  source = "git::https://github.com/fortytwoservices/az-tf-mlz-virtual-network-gateway.git?ref=vX.Y.Z"

  name          = "vgw-hub-sdc"
  parent_id     = "/subscriptions/<subscription>/resourceGroups/<resource group>"
  location      = "swedencentral"
  subnet_id     = "<GatewaySubnet ID>"
  active_active = true
  bgp           = { asn = 65010 }
  ip_configurations = {
    ipconfig1 = { public_ip = { name = "pip-vgw-hub-sdc-1" } }
    ipconfig2 = { public_ip = { name = "pip-vgw-hub-sdc-2" } }
  }
  local_network_gateways = {
    oslo = { name = "lgw-oslo", gateway_ip_address = "<device IP>", address_prefixes = ["10.50.0.0/16"] }
  }
  connections = {
    oslo = { name = "con-oslo", local_network_gateway_key = "oslo" }
  }
  connection_secrets = { oslo = var.oslo_shared_key } # an ephemeral variable or an ephemeral resource's value
}
```

The examples deploy an active-active VPN gateway with BGP, point-to-site and one site (`default`), and an
ExpressRoute gateway (`express_route`).
