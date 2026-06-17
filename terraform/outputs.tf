output "aks_name" {
  description = "AKS cluster name (null when the ephemeral cluster is not deployed)."
  value       = one(azurerm_kubernetes_cluster.aks[*].name)
}

output "aks_oidc_issuer_url" {
  description = "Cluster OIDC issuer URL (null when the ephemeral cluster is not deployed)."
  value       = one(azurerm_kubernetes_cluster.aks[*].oidc_issuer_url)
}

output "acr_login_server" {
  description = "ACR login server for image push/pull."
  value       = azurerm_container_registry.acr.login_server
}

output "grafana_endpoint" {
  description = "Azure Managed Grafana endpoint (null when the ephemeral cluster is not deployed)."
  value       = one(azurerm_dashboard_grafana.amg[*].endpoint)
}

output "swa_default_hostname" {
  description = "Static Web App default hostname (CNAME target for the front)."
  value       = azurerm_static_web_app.swa.default_host_name
}

output "swa_api_key" {
  description = "SWA deployment token (consumed by the SWA deploy action)."
  value       = azurerm_static_web_app.swa.api_key
  sensitive   = true
}

output "cv_app_client_id" {
  description = "Client ID for id-cv-app (annotate the cv-site ServiceAccount)."
  value       = azurerm_user_assigned_identity.cv_app.client_id
}

output "gh_oidc_client_id" {
  description = "Client ID for id-gh-oidc-newcode-cv (azure/login client-id)."
  value       = azurerm_user_assigned_identity.gh_oidc.client_id
}

output "tailscale_operator_hostname" {
  description = "MagicDNS name of the Tailscale operator API-server proxy; CI installs the operator under this name and reaches the private AKS API at it over the tailnet."
  value       = var.tailscale_operator_hostname
}

output "tunnel_token" {
  description = "Cloudflare tunnel token; pushed to Key Vault / k8s secret at deploy."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.cv.token
  sensitive   = true
}
