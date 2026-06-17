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

# The deployer (the local user on the first apply, the gh_oidc MI in CI) must be
# able to write the tunnel-token secret. Secrets Officer is the least-privilege
# role that allows set/get/list on SECRETS only — no key/cert or purge rights.
# This single grant on the *current* caller covers both local and CI, so there is
# no second, overlapping Key Vault Administrator assignment to collide with it.
resource "azurerm_role_assignment" "kv_secrets_officer_deployer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Tunnel token secret. The literal value is a placeholder (REPLACE_ME); the real
# token is the sensitive output of the cloudflare tunnel data source and is written
# out-of-band at deploy (CI), so no secret value lives in the repo or default state.
resource "azurerm_key_vault_secret" "cloudflare_tunnel_token" {
  name         = "cloudflare-tunnel-token"
  value        = var.cloudflare_tunnel_token_placeholder
  key_vault_id = azurerm_key_vault.kv.id
  content_type = "cloudflare-tunnel-token"

  # No expiration_date on purpose: an expiring tunnel token would silently drop the
  # AKS ingress mid-proof. Rotation is handled out-of-band, not by a TF expiry.

  # Deploy overwrites .value with the real token; ignore drift so TF doesn't revert it.
  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [azurerm_role_assignment.kv_secrets_officer_deployer]
}

# App workload identity reads secrets (tunnel token) via CSI + Workload Identity.
resource "azurerm_role_assignment" "kv_app_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.cv_app.principal_id
}
