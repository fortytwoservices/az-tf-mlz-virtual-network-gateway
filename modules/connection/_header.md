# Connection

One virtual network gateway connection (`Microsoft.Network/connections`): site-to-site `IPsec` to a
local network gateway, `Vnet2Vnet` to another Azure VPN gateway, or `ExpressRoute` to a circuit. The
root module calls it once per `connections` entry; it can also be called alone with a gateway's ID.

- The pre-shared key (and an ExpressRoute authorization key) is ephemeral and write-only: sent to Azure
  on create and whenever `secret_version` changes, never stored in state.
- Every setting of the connection type is sent, empty when unset, so removing one reaches Azure.
- Connections to one gateway are written one at a time. The type, the gateways, the circuit, the IKE
  protocol, the connection mode and the DPD timeout replace the connection (azurerm marks them
  ForceNew), and so do the local network gateway (Azure refuses to change it) and any change in
  `replace_triggers` (the root passes the gateway's own).
- Lock, role assignments and diagnostic settings (metrics only: a connection has no log categories).
