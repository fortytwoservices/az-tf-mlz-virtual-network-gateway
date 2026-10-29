# Default example

A resource group, a virtual network with `GatewaySubnet` and a Log Analytics workspace, then an
active-active `VpnGw1AZ` VPN gateway with BGP (ASN 65010), three public IP addresses the module creates
(two instances and point-to-site), point-to-site with Microsoft Entra ID authentication in the current
tenant, one on-premises site with BGP and its IPsec connection, and the gateway's logs and metrics and
the connection's metrics sent to the workspace. In Sweden Central.

The pre-shared key is an ephemeral random password: it never reaches state. The site's address is from
a documentation range, so the tunnel never comes up.

Run it with `scripts/e2e.sh examples/default`: apply, a second plan that must be empty, destroy. The
gateway is billed by the hour from the moment it exists, and creating or deleting it takes up to 45
minutes, so do not leave it running.
