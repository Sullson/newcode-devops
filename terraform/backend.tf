terraform {
  # Chicken-and-egg: this storage account / container does not exist on a fresh
  # subscription. scripts/bootstrap-backend.sh creates the RG + storage account
  # stnewcodecvtf + container tfstate ONCE before the very first `terraform init`.
  # CI authenticates to the backend via OIDC (use_oidc/use_azuread_auth), so no
  # access keys are stored anywhere.
  backend "azurerm" {
    resource_group_name  = "rg-newcode-cv"
    storage_account_name = "stnewcodecvtf"
    container_name       = "tfstate"
    key                  = "cv.tfstate"
    # AAD data-plane auth (no storage keys). OIDC is toggled by the ARM_USE_OIDC
    # env var — set in CI, absent locally so `terraform init` uses your az login.
    use_azuread_auth = true
  }
}
