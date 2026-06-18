resource "azurerm_log_analytics_workspace" "log" {
  name                = "log-newcode-cv"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# Managed Prometheus metrics store. ServiceMonitors from the cluster scrape into this.
# Ephemeral: only meaningful while the cluster is up, and gated to keep the
# always-on footprint near-zero (Managed Grafana Standard bills ~$65/mo idle).
resource "azurerm_monitor_workspace" "amw" {
  count               = var.deploy_aks ? 1 : 0
  name                = "amw-newcode-cv"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = local.tags
}

resource "azurerm_dashboard_grafana" "amg" {
  # Ephemeral — Managed Grafana Standard has a standing hourly charge, so it
  # lives only during a proof run (when there are cluster metrics to show).
  count                 = var.deploy_aks ? 1 : 0
  name                  = "amg-newcode-cv"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  grafana_major_version = 12
  sku                   = "Standard"

  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.amw[0].id
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

# Grafana's MSI must read metrics from the monitor workspace to render dashboards.
resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  count                = var.deploy_aks ? 1 : 0
  scope                = azurerm_monitor_workspace.amw[0].id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.amg[0].identity[0].principal_id
}

# The deploying identity (CI/operator) gets dashboard edit rights.
resource "azurerm_role_assignment" "grafana_admin" {
  count                = var.deploy_aks ? 1 : 0
  scope                = azurerm_dashboard_grafana.amg[0].id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}
