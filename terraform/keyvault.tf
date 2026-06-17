resource "azurerm_key_vault" "kv" {
  name                = "kv-newcode-cv"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tenant_id           = var.tenant_id
  sku_name            = "standard"
  # RBAC mode (no access policies): all grants are role assignments below.
  rbac_authorization_enabled = true
  tags                       = local.tags
}

# The CI/operator identity must be able to write the tunnel token secret.
resource "azurerm_role_assignment" "kv_admin_deployer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Tunnel token secret. The literal value is a placeholder (REPLACE_ME); the real
# token is the sensitive output of the cloudflare tunnel data source and is written
# out-of-band at deploy (CI), so no secret value lives in the repo or default state.
resource "azurerm_key_vault_secret" "cloudflare_tunnel_token" {
  name         = "cloudflare-tunnel-token"
  value        = var.cloudflare_tunnel_token_placeholder
  key_vault_id = azurerm_key_vault.kv.id

  # Deploy overwrites .value with the real token; ignore drift so TF doesn't revert it.
  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [azurerm_role_assignment.kv_admin_deployer]
}

# App workload identity reads secrets (tunnel token) via CSI + Workload Identity.
resource "azurerm_role_assignment" "kv_app_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.cv_app.principal_id
}
