# ExpressRoute example

A resource group, a virtual network with a /26 `GatewaySubnet` (the least `ErGwScale` takes) and a Log
Analytics workspace, then an ExpressRoute gateway (`ErGwScale` at one fixed scale unit) whose public IP address Azure assigns and
manages, with its logs and metrics sent to the workspace. In Sweden Central. It has no connection:
connecting it needs an ExpressRoute circuit, which is billed by the month.

Run it with `scripts/e2e.sh examples/express_route`: apply, a second plan that must be empty, destroy.
The gateway is billed by the hour from the moment it exists, and creating or deleting it takes up to 45
minutes, so do not leave it running.
