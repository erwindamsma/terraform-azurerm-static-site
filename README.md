# terraform-azurerm-static-site

An Azure Static Web App and, optionally, its custom domain. Works with OpenTofu
and Terraform alike.

Public because module sources have to be fetchable without credentials — a
private source would need a stored token in CI, which the projects using this
deliberately do not have. Nothing here is specific to any one deployment.

## Usage

```hcl
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  use_oidc        = true
}

module "site" {
  source = "github.com/erwindamsma/terraform-azurerm-static-site"

  resource_group_name = "example-rg"
  site_name           = "example-site"
  custom_domain       = "example.com"
}

output "default_host_name" {
  value = module.site.default_host_name
}
```

Unpinned on purpose: every consumer picks up changes on its next `init`. Add
`?ref=<tag>` if you would rather a project stayed put.

## Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `resource_group_name` | string | — | Existing group to create the app in. Read, never managed. |
| `site_name` | string | — | Name of the Static Web App. |
| `custom_domain` | string | `""` | Domain to attach; empty for none. See below. |
| `sku` | string | `"Free"` | `Free` or `Standard`. |
| `tags` | map(string) | `{}` | Merged over `managed_by` and `project`. |

## Outputs

| Name | Description |
| --- | --- |
| `default_host_name` | Azure-assigned hostname — the CNAME target |
| `static_web_app_id` | Resource ID, for attaching things this module does not cover |
| `custom_domain` | Attached domain, or empty |

## Attaching a domain takes two applies

Azure validates ownership by resolving the domain's CNAME to the app's hostname,
and that hostname does not exist until the app does. So:

1. apply with `custom_domain = ""` → note `default_host_name`
2. CNAME your domain at it
3. set `custom_domain` and apply again

Apex domains work if your DNS provider flattens CNAMEs. Cloudflare does.

## No provider or backend block in here

A module inherits the caller's provider. Declaring one inside would stop the
module working with `count`/`for_each` and make it impossible to remove cleanly.
Backends are a root-module concern. Both belong in the repo that calls this.

## Adopting it for a site that already exists

Moving a resource into a module changes its state address, and Terraform reads
that as *destroy the old one, create a new one* — an outage, plus a custom domain
that has to revalidate. Tell it what actually happened instead:

```hcl
moved {
  from = azurerm_static_web_app.site
  to   = module.site.azurerm_static_web_app.site
}

moved {
  from = azurerm_static_web_app_custom_domain.site
  to   = module.site.azurerm_static_web_app_custom_domain.site[0]
}
```

The `[0]` matters: the domain is behind `count`, so inside the module it is a
list. Plan should say **moved**, never **replaced**. Delete the blocks once
applied.
