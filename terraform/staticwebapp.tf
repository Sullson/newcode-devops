# Always-on free front (Astro static output), served independently of the AKS demo.
resource "azurerm_static_web_app" "swa" {
  name                = "swa-newcode-cv"
  resource_group_name = azurerm_resource_group.rg.name
  # SWA Free is offered in a limited set of regions; West Europe is the nearest.
  location = "westeurope"
  sku_tier = "Free"
  sku_size = "Free"
  tags     = local.tags
}
