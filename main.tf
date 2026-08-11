# An Azure Static Web App and, optionally, its custom domain.
#
# Deliberately absent: `provider` and `backend` blocks. A module inherits the
# calling configuration's provider, and declaring one here would stop the module
# being usable with count/for_each and make it impossible to remove cleanly.
# Backends are a root-module concern only.

terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}

variable "resource_group_name" {
  description = "Existing resource group to create the app in. Read, never managed -- a module has no business destroying the group it was pointed at."
  type        = string
}

variable "site_name" {
  description = "Name of the Static Web App."
  type        = string
}

variable "custom_domain" {
  description = <<-EOT
    Domain to attach, or "" for none.

    Leave empty on the first apply. Azure validates ownership by resolving the
    domain's CNAME to the app's hostname, and that hostname does not exist until
    the app has been created — so attaching a domain in the same apply that
    creates the app cannot work.
  EOT
  type        = string
  default     = ""
}

variable "sku" {
  description = "Free or Standard. Free covers custom domains, managed TLS, global CDN and 3 preview environments; Standard adds an SLA and private endpoints."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard"], var.sku)
    error_message = "sku must be Free or Standard."
  }
}

variable "tags" {
  description = "Extra tags, merged over the defaults."
  type        = map(string)
  default     = {}
}

data "azurerm_resource_group" "project" {
  name = var.resource_group_name
}

resource "azurerm_static_web_app" "site" {
  name                = var.site_name
  resource_group_name = data.azurerm_resource_group.project.name
  location            = data.azurerm_resource_group.project.location

  sku_tier = var.sku
  sku_size = var.sku

  tags = merge({
    managed_by = "opentofu"
    project    = var.site_name
  }, var.tags)

  lifecycle {
    # Azure records a repo link when an app is connected through the portal. It
    # cannot be declared here -- the provider requires repository_token
    # alongside the url and branch, which would put a GitHub PAT into state --
    # and leaving it out plans to null the link on every apply. Ignoring is the
    # only option that neither stores a secret nor churns live state.
    # Deployments carry their own token and do not use the link.
    ignore_changes = [repository_url, repository_branch]
  }
}

# Created only once custom_domain is set, which has to be a second apply: Azure
# proves ownership by resolving the CNAME, and the target hostname does not
# exist until the app above does.
resource "azurerm_static_web_app_custom_domain" "site" {
  count = var.custom_domain == "" ? 0 : 1

  static_web_app_id = azurerm_static_web_app.site.id
  domain_name       = var.custom_domain
  validation_type   = "cname-delegation"

  lifecycle {
    # validation_type is write-only: Azure accepts it at creation and never
    # returns it. Without this, an imported or re-read domain looks changed on
    # every plan and gets replaced -- detaching a live domain for as long as
    # revalidation takes.
    ignore_changes = [validation_type]
  }
}

output "default_host_name" {
  description = "Azure-assigned hostname. Point your CNAME here, and use it to check the origin directly."
  value       = azurerm_static_web_app.site.default_host_name
}

output "static_web_app_id" {
  description = "Resource ID, for attaching things the module does not cover."
  value       = azurerm_static_web_app.site.id
}

output "custom_domain" {
  description = "Attached domain, or empty if none yet."
  value       = var.custom_domain
}
