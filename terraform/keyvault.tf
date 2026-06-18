resource "azurerm_key_vault" "kv" {
  name                = "kv-newcode-cv"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tenant_id           = var.tenant_id
  sku_name            = "standard"
  # RBAC mode (no access policies): all grants are role assignments below.
  rbac_authorization_enabled = true

  # Soft delete is always on; 7 days is the minimum (short, so a torn-down demo
  # frees the vault name quickly). Purge protection is parametrized: production
  # sets it true (anti-ransomware / anti-accidental-delete — the control that
  # backs the "protects confidential data" claim), but it is irreversible and
  # blocks recreating this vault name for the retention window, so the ephemeral
  # demo defaults it off. See var.kv_purge_protection.
  soft_delete_retention_days = 7
  purge_protection_enabled   = var.kv_purge_protection

  # Public endpoint retained on purpose, gated by RBAC + AAD data-plane auth: the
  # first apply runs from a laptop, CI writes the token from a GitHub-hosted
  # runner, and the AKS CSI driver reads over the public endpoint. Locking this to
  # private endpoints would need VNet integration + private DNS for no real gain on
  # a single-tenant demo — that is the production step, called out in SECURITY.md.

  tags = local.tags
}

# The deploy workflow's "Sync tunnel token to Key Vault" step (run as the gh_oidc CI
# identity) is the sole writer of the tunnel-token secret. Secrets Officer is the
# least-privilege role that allows set/get/list on SECRETS only — no key/cert or
# purge rights. Pinned to the gh_oidc MI (not the *current* caller): the secret is no
# longer a Terraform resource, so a CI apply never reads Key Vault data-plane and
# cannot deadlock on a refresh that precedes this grant.
resource "azurerm_role_assignment" "kv_secrets_officer_deployer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.gh_oidc.principal_id
}

# The cloudflare-tunnel-token secret is intentionally NOT a Terraform resource: the
# deploy workflow writes it out-of-band from the cloudflare tunnel's sensitive output
# (so no secret value lives in the repo or state). Keeping it out of Terraform means a
# CI apply never touches Key Vault data-plane — no getSecret on refresh — which is what
# previously deadlocked the first CI apply (refresh ran before the deployer grant it
# depended on). The in-cluster cloudflared reads the secret via CSI + Workload Identity
# (kv_app_secrets_user below).

# App workload identity reads secrets (tunnel token) via CSI + Workload Identity.
resource "azurerm_role_assignment" "kv_app_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.cv_app.principal_id
}
