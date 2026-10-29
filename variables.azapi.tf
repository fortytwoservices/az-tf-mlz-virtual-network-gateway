variable "ignore_body_changes" {
  type = object({
    network_virtual_network_gateways = optional(list(string), [])
    authorization_locks              = optional(list(string), [])
    authorization_role_assignments   = optional(list(string), [])
    insights_diagnostic_settings     = optional(list(string), [])

    network_public_ip_addresses = optional(object({
      network_public_ip_addresses    = optional(list(string), [])
      authorization_locks            = optional(list(string), [])
      authorization_role_assignments = optional(list(string), [])
      insights_diagnostic_settings   = optional(list(string), [])
    }), {})
    network_local_network_gateways = optional(object({
      network_local_network_gateways = optional(list(string), [])
      authorization_locks            = optional(list(string), [])
      authorization_role_assignments = optional(list(string), [])
    }), {})
    network_connections = optional(object({
      network_connections            = optional(list(string), [])
      authorization_locks            = optional(list(string), [])
      authorization_role_assignments = optional(list(string), [])
    }), {})
  })
  default     = {}
  description = <<DESCRIPTION
Paths in each resource's `body` whose changes the AzAPI provider ignores. Prefer Terraform's `lifecycle.ignore_changes` when the paths are static; use this variable when the paths must be derived from variables or other non-static values.

Paths use dot notation, for example `properties.vpnClientConfiguration`. Individual list items cannot be targeted; ignore the whole list property instead. Configuration changes at an ignored path are **not** sent to Azure until that path is removed from the list. Changes take effect only after an apply, because the value is held in provider-private state.

- `network_virtual_network_gateways` - Ignored body paths for the gateway.
- `authorization_locks` - Ignored body paths for the gateway's lock.
- `authorization_role_assignments` - Ignored body paths for the gateway's role assignments.
- `insights_diagnostic_settings` - Ignored body paths for the gateway's diagnostic settings.
- `network_public_ip_addresses` - Slot for the `az-tf-mlz-public-ip` calls (its `network_public_ip_addresses` and interface keys).
- `network_local_network_gateways` - Slot for `modules/local_network_gateway` (its `network_local_network_gateways` and interface keys).
- `network_connections` - Slot for `modules/connection` (its `network_connections` and interface keys).
DESCRIPTION
  nullable    = false
}

variable "resource_types" {
  type = object({
    network_virtual_network_gateways = optional(string, "Microsoft.Network/virtualNetworkGateways@2025-07-01")
    authorization_locks              = optional(string, "Microsoft.Authorization/locks@2020-05-01")
    authorization_role_assignments   = optional(string, "Microsoft.Authorization/roleAssignments@2022-04-01")
    insights_diagnostic_settings     = optional(string, "Microsoft.Insights/diagnosticSettings@2021-05-01-preview")

    network_public_ip_addresses = optional(object({
      network_public_ip_addresses    = optional(string)
      authorization_locks            = optional(string)
      authorization_role_assignments = optional(string)
      insights_diagnostic_settings   = optional(string)
    }), {})
    network_local_network_gateways = optional(object({
      network_local_network_gateways = optional(string)
      authorization_locks            = optional(string)
      authorization_role_assignments = optional(string)
    }), {})
    network_connections = optional(object({
      network_connections            = optional(string)
      authorization_locks            = optional(string)
      authorization_role_assignments = optional(string)
    }), {})
  })
  default     = {}
  description = <<DESCRIPTION
Override the AzAPI `<provider>/<resource>@<api-version>` strings used by this module and the modules it calls. Each key defaults to a tested value; supply only the keys you want to override.

- `network_virtual_network_gateways` - The gateway.
- `authorization_locks` - The lock on the gateway.
- `authorization_role_assignments` - Role assignments on the gateway.
- `insights_diagnostic_settings` - Diagnostic settings on the gateway.
- `network_public_ip_addresses` - Slot for the `az-tf-mlz-public-ip` calls. Defaults live in that module.
- `network_local_network_gateways` - Slot for `modules/local_network_gateway`. Defaults live in that module.
- `network_connections` - Slot for `modules/connection`. Defaults live in that module.
DESCRIPTION
  nullable    = false
}

variable "retry" {
  type = object({
    error_message_regex  = optional(list(string), ["AnotherOperationInProgress"])
    interval_seconds     = optional(number, 30)
    max_interval_seconds = optional(number, 300)
  })
  default     = {}
  description = <<DESCRIPTION
Retry configuration applied to every `azapi` resource managed by the module and the modules it calls. Defaults retry `AnotherOperationInProgress`, which Azure returns while another operation runs on the same gateway or virtual network; any field can be overridden.

- `error_message_regex`  - (Optional) A list of regex patterns matching error messages that trigger a retry. Defaults to `["AnotherOperationInProgress"]`.
- `interval_seconds`     - (Optional) Initial interval between retries in seconds. Defaults to `30`.
- `max_interval_seconds` - (Optional) Maximum interval between retries in seconds. Defaults to `300`.

See <https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource#retry> for full semantics.
DESCRIPTION
}

variable "timeouts" {
  type = object({
    create = optional(string, "90m")
    read   = optional(string)
    update = optional(string, "90m")
    delete = optional(string, "90m")
  })
  default     = {}
  description = <<DESCRIPTION
Per-operation timeouts applied to every `azapi` resource managed by the module and the modules it calls. Creating, changing or deleting a gateway takes up to 45 minutes (Microsoft Learn), more than the provider's 30-minute default, so create, update and delete default to `90m`; any field can be overridden. Each value is a Go duration string (e.g. `30m`, `1h`).

- `create` - (Optional) Timeout for create operations. Defaults to `90m`.
- `read`   - (Optional) Timeout for read operations. Defaults to the provider's.
- `update` - (Optional) Timeout for update operations. Defaults to `90m`.
- `delete` - (Optional) Timeout for delete operations. Defaults to `90m`.
DESCRIPTION
}
