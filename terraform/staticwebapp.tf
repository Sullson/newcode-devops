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

# Bind the custom domain so SWA serves newcode.<zone> with its OWN managed TLS
# cert. cname-delegation validates the CNAME (cloudflare.tf, DNS-only) that points
# this host at the SWA default hostname. The front's Cloudflare proxy is OFF so
# SWA can validate the CNAME and terminate TLS itself; the tunnel hosts
# (aks-newcode / grafana-newcode) stay proxied. Without this binding a proxied
# request returns HTTP 526 (origin has no cert/route for the host).
resource "azurerm_static_web_app_custom_domain" "front" {
  static_web_app_id = azurerm_static_web_app.swa.id
  domain_name       = "newcode.${var.cloudflare_zone}"
  validation_type   = "cname-delegation"

  depends_on = [cloudflare_dns_record.front]
}
