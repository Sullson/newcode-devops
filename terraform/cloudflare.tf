# Zone lookup by name (v5: filter block, exposes .zone_id).
data "cloudflare_zone" "zone" {
  filter = {
    name = var.cloudflare_zone
  }
}

# Per-tunnel secret (>=32 bytes, base64) required by the cloudflared resource.
resource "random_bytes" "tunnel_secret" {
  length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "cv" {
  account_id    = var.cloudflare_account_id
  name          = "cv"
  tunnel_secret = random_bytes.tunnel_secret.base64
  # "cloudflare" = ingress managed here via the _config resource (remote config).
  config_src = "cloudflare"
}

# v5 ingress is an attribute (config = { ingress = [...] }), not nested blocks.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "cv" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cv.id

  config = {
    ingress = [
      {
        hostname = "aks.newcode.${var.cloudflare_zone}"
        service  = "http://cv-site.cv.svc.cluster.local:80"
      },
      # Catch-all required by cloudflared (last rule must match everything).
      {
        service = "http_status:404"
      },
    ]
  }
}

# On-demand AKS proof host -> the tunnel. Proxied so the origin (cluster) stays hidden.
resource "cloudflare_dns_record" "aks" {
  zone_id = data.cloudflare_zone.zone.zone_id
  name    = "aks.newcode.${var.cloudflare_zone}"
  type    = "CNAME"
  # v5 has no .cname attribute; the tunnel CNAME target is <tunnel_id>.cfargotunnel.com.
  content = "${cloudflare_zero_trust_tunnel_cloudflared.cv.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1 # 1 = automatic; required when proxied.
  comment = "CF Tunnel: cv (AKS proof)"
}

# Always-on front -> Azure Static Web App. Proxied so it sits behind Cloudflare too.
resource "cloudflare_dns_record" "front" {
  zone_id = data.cloudflare_zone.zone.zone_id
  name    = "newcode.${var.cloudflare_zone}"
  type    = "CNAME"
  content = azurerm_static_web_app.swa.default_host_name
  proxied = true
  ttl     = 1
  comment = "Azure Static Web App front"
}

# v5: tunnel token is fetched via data source (no read-only attr on the resource).
data "cloudflare_zero_trust_tunnel_cloudflared_token" "cv" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cv.id
}
