resource "azurerm_kubernetes_cluster" "aks" {
  # Ephemeral: created only on the on-demand proof run (deploy_aks=true). Teardown
  # flips it false so this cluster and its cluster-bound dependents are removed,
  # while the always-on front (SWA, DNS, ACR, Key Vault, identities, monitoring,
  # Cloudflare tunnel) stays put. This is what makes the hybrid "near-zero cost".
  count = var.deploy_aks ? 1 : 0

  name                = "aks-newcode-cv"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  dns_prefix          = "aksnewcodecv"

  # PRIVATE API server: zero inbound from the internet. CI reaches kube-apiserver
  # through the Tailscale Kubernetes Operator's API-server proxy over the tailnet.
  private_cluster_enabled = true

  # Workload Identity (OIDC) so the app SA can read Key Vault without stored creds.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name       = "system"
    node_count = var.node_count
    vm_size    = var.vm_size
  }

  identity {
    type = "SystemAssigned"
  }

  # Azure RBAC for Kubernetes authz — RBAC Cluster Admin role drives kubectl access.
  role_based_access_control_enabled = true
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = var.tenant_id
  }

  # CSI Secrets Store driver: tunnel token comes from Key Vault, not the repo.
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  # Managed Prometheus add-on; metrics land in amw-newcode-cv via the DCR below.
  monitor_metrics {}

  # Container Insights logs to Log Analytics with MSI auth (no workspace keys).
  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.log.id
    msi_auth_for_monitoring_enabled = true
  }

  tags = local.tags
}

# Kubelet identity needs AcrPull to pull cv-site images.
resource "azurerm_role_assignment" "kubelet_acrpull" {
  count                            = var.deploy_aks ? 1 : 0
  scope                            = azurerm_container_registry.acr.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.aks[0].kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

# --- Managed Prometheus: DCR + association wiring the cluster to amw-newcode-cv ---
resource "azurerm_monitor_data_collection_endpoint" "prom" {
  count               = var.deploy_aks ? 1 : 0
  name                = "dce-prom-newcode-cv"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  kind                = "Linux"
  tags                = local.tags
}

resource "azurerm_monitor_data_collection_rule" "prom" {
  count                       = var.deploy_aks ? 1 : 0
  name                        = "dcr-prom-newcode-cv"
  resource_group_name         = azurerm_resource_group.rg.name
  location                    = azurerm_resource_group.rg.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prom[0].id
  kind                        = "Linux"

  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.amw[0].id
      name               = "amw"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["amw"]
  }

  data_sources {
    prometheus_forwarder {
      streams = ["Microsoft-PrometheusMetrics"]
      name    = "PrometheusForwarder"
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "prom" {
  # The DCE/DCR above are persistent (idle, ~free). Only the cluster association
  # is ephemeral — it can't exist without the cluster.
  count                   = var.deploy_aks ? 1 : 0
  name                    = "dcra-prom-newcode-cv"
  target_resource_id      = azurerm_kubernetes_cluster.aks[0].id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.prom[0].id
}
