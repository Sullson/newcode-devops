resource "azurerm_container_registry" "acr" {
  name                = "acrnewcodecv"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  # Basic by design (~$5/mo). Image integrity is enforced in CI — Trivy scan +
  # cosign keyless sign/verify — not by Premium-only ACR features (content trust,
  # quarantine, geo-replication, private networking, Defender scanning), which
  # would multiply cost for no added assurance on a single-tenant demo registry.
  sku = "Basic"

  # No admin user: pushes use the OIDC identity (AcrPush), pulls use kubelet MI (AcrPull).
  admin_enabled = false
  tags          = local.tags
}
