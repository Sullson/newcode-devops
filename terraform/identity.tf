# --- GitHub Actions OIDC identity: CI assumes this via workload-identity federation ---
resource "azurerm_user_assigned_identity" "gh_oidc" {
  name                = "id-gh-oidc-newcode-cv"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = local.tags
}

locals {
  # Federated subjects scope which GitHub contexts may mint a token for this MI.
  gh_oidc_subjects = {
    main = "repo:${var.github_repo}:ref:refs/heads/main"
    pr   = "repo:${var.github_repo}:pull_request"
    prod = "repo:${var.github_repo}:environment:production"
  }
}

resource "azurerm_federated_identity_credential" "gh_oidc" {
  for_each            = local.gh_oidc_subjects
  name                = "gh-${each.key}"
  resource_group_name = azurerm_resource_group.rg.name
  parent_id           = azurerm_user_assigned_identity.gh_oidc.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = each.value
}

resource "azurerm_role_assignment" "gh_contributor_rg" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.gh_oidc.principal_id
}

resource "azurerm_role_assignment" "gh_acrpush" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.gh_oidc.principal_id
}

# RBAC Cluster Admin so CI can helm-deploy through the Tailscale API proxy.
# Ephemeral with the cluster (its scope is the cluster id).
resource "azurerm_role_assignment" "gh_aks_admin" {
  count                = var.deploy_aks ? 1 : 0
  scope                = azurerm_kubernetes_cluster.aks[0].id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = azurerm_user_assigned_identity.gh_oidc.principal_id
}

# Key Vault Administrator scoped to the vault only (write tunnel token at deploy).
resource "azurerm_role_assignment" "gh_kv_admin" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = azurerm_user_assigned_identity.gh_oidc.principal_id
}

# --- App workload identity: federated to the AKS OIDC issuer, reads Key Vault ---
resource "azurerm_user_assigned_identity" "cv_app" {
  name                = "id-cv-app"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = local.tags
}

# Subject = the k8s ServiceAccount cv-site in namespace cv; trust is the cluster's
# OIDC issuer URL. This is what makes Workload Identity tokens exchangeable for AAD.
# Ephemeral: the issuer URL is unique per cluster, so this credential is recreated
# each proof run. The identity itself (id-cv-app) is persistent.
resource "azurerm_federated_identity_credential" "cv_app" {
  count               = var.deploy_aks ? 1 : 0
  name                = "cv-site-sa"
  resource_group_name = azurerm_resource_group.rg.name
  parent_id           = azurerm_user_assigned_identity.cv_app.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks[0].oidc_issuer_url
  subject             = "system:serviceaccount:cv:cv-site"
}
