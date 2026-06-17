provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  # Auth is ENV-driven, not hardcoded: GitHub Actions sets ARM_USE_OIDC=true
  # (workload-identity federation, no stored secret); locally it is unset, so
  # Terraform falls back to your `az login` (CLI). Hardcoding use_oidc=true here
  # would break the first manual local apply.
  features {}
}

provider "cloudflare" {
  # CF API token is injected from GitHub Actions secrets as CLOUDFLARE_API_TOKEN
  # (env var the provider reads); never declared as a TF variable with a value.
}

provider "random" {}

data "azurerm_client_config" "current" {}

locals {
  tags = var.tags
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-newcode-cv"
  location = var.location
  tags     = local.tags
}
