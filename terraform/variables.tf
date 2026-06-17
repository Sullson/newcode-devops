variable "subscription_id" {
  description = "Azure subscription ID (provided at deploy time via OIDC; never committed)."
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID."
  type        = string
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "swedencentral"
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID that owns the zone and tunnel."
  type        = string
}

variable "cloudflare_zone" {
  description = "Cloudflare-managed DNS zone."
  type        = string
  default     = "msulawiak.pl"
}

variable "github_repo" {
  description = "owner/repo used as the subject of GitHub OIDC federated credentials."
  type        = string
  default     = "sullson/newcode-devops"
}

variable "tailscale_tailnet" {
  description = "Tailscale tailnet (org) the CI joins ephemerally to reach the private AKS API. Informational; the OAuth client/key is supplied to CI, never to TF."
  type        = string
  default     = "REPLACE_ME"
}

variable "tailscale_operator_hostname" {
  description = "MagicDNS hostname of the Tailscale Kubernetes Operator's API-server proxy. CI installs the operator with this name and reaches the PRIVATE AKS API at it over the tailnet (no public API endpoint)."
  type        = string
  default     = "aks-newcode-cv-operator"
}

variable "deploy_aks" {
  description = "Ephemeral toggle. false (default) = only the always-on persistent infra (SWA front, DNS, ACR, Key Vault, identities, monitoring, Cloudflare tunnel). true = ALSO create the AKS cluster and its cluster-bound dependents. The deploy-aks workflow flips this true to prove the cluster, then false to tear ONLY the cluster back down — never a full destroy, so the live front survives."
  type        = bool
  default     = false
}

variable "node_count" {
  description = "System node pool size. One node is enough for this demo cluster."
  type        = number
  default     = 1
}

variable "vm_size" {
  description = "VM SKU for the system node pool. Small/cheap by design."
  type        = string
  default     = "Standard_B2s"
}

variable "cloudflare_tunnel_token_placeholder" {
  description = "Initial Key Vault value for the tunnel token. The real token is the sensitive output of the cloudflare tunnel data source and is set out-of-band at deploy; this keeps the secret resource declarable without a literal."
  type        = string
  default     = "REPLACE_ME"
  sensitive   = true
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default = {
    project = "newcode-devops"
    owner   = "sullson"
    managed = "terraform"
  }
}
