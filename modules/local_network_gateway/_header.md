# Local network gateway

One local network gateway (`Microsoft.Network/localNetworkGateways`): an on-premises site, its VPN
device's public IP address or FQDN, its address ranges and its BGP settings. The root module calls it
once per `local_network_gateways` entry; it can also be called alone, for a site that connections in
another state use.

Every setting is sent, null or empty when unset, so removing one reaches Azure. Azure refuses a local
network gateway with neither address ranges nor BGP settings, and diagnostic settings on any.
