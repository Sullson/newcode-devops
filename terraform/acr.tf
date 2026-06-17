resource "azurerm_container_registry" "acr" {
  name                = "acrnewcodecv"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  # No admin user: pushes use the OIDC identity (AcrPush), pulls use kubelet MI (AcrPull).
  admin_enabled = false
  tags          = local.tags
}
