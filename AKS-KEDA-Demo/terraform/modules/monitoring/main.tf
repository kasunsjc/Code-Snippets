resource "azapi_resource" "prometheus_workspace" {
  type      = "Microsoft.Monitor/accounts@2023-04-03"
  name      = "${var.base_name}-prometheus"
  parent_id = var.resource_group_id
  location  = var.location
  tags      = var.tags
  body      = {}

  response_export_values = ["properties.metrics.prometheusQueryEndpoint"]
}

locals {
  grafana_name = length("${var.base_name}-grafana") > 23 ? substr(replace(var.base_name, "-", ""), 0, 23) : "${var.base_name}-grafana"
}

resource "azapi_resource" "grafana" {
  type      = "Microsoft.Dashboard/grafana@2023-09-01"
  name      = local.grafana_name
  parent_id = var.resource_group_id
  location  = var.location
  tags      = var.tags
  response_export_values = [
    "identity.principalId",
    "properties.endpoint"
  ]

  identity {
    type = "SystemAssigned"
  }

  body = {
    sku = {
      name = "Standard"
    }
    properties = {
      publicNetworkAccess = "Enabled"
      grafanaIntegrations = {
        azureMonitorWorkspaceIntegrations = [
          {
            azureMonitorWorkspaceResourceId = azapi_resource.prometheus_workspace.id
          }
        ]
      }
    }
  }
}

locals {
  grafana_principal_id = try(azapi_resource.grafana.output["identity"]["principalId"], "")
}

resource "azapi_resource" "dce" {
  type      = "Microsoft.Insights/dataCollectionEndpoints@2022-06-01"
  name      = "MSProm-${var.location}-${var.base_name}"
  parent_id = var.resource_group_id
  location  = var.location
  tags      = var.tags
  body = {
    kind = "Linux"
    properties = {
      networkAcls = {
        publicNetworkAccess = "Enabled"
      }
    }
  }
}

resource "azapi_resource" "dcr" {
  type      = "Microsoft.Insights/dataCollectionRules@2023-03-11"
  name      = "MSProm-${var.location}-${var.base_name}"
  parent_id = var.resource_group_id
  location  = var.location
  tags      = var.tags
  body = {
    properties = {
      dataCollectionEndpointId = azapi_resource.dce.id
      dataSources = {
        prometheusForwarder = [
          {
            name               = "PrometheusDataSource"
            streams            = ["Microsoft-PrometheusMetrics"]
            labelIncludeFilter = {}
          }
        ]
      }
      destinations = {
        monitoringAccounts = [
          {
            accountResourceId = azapi_resource.prometheus_workspace.id
            name              = "MonitoringAccount1"
          }
        ]
      }
      dataFlows = [
        {
          streams      = ["Microsoft-PrometheusMetrics"]
          destinations = ["MonitoringAccount1"]
        }
      ]
    }
  }
}

resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  depends_on                       = [azapi_resource.grafana]
  scope                            = azapi_resource.prometheus_workspace.id
  role_definition_name             = "Monitoring Reader"
  principal_id                     = local.grafana_principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "grafana_monitoring_data_reader" {
  depends_on                       = [azapi_resource.grafana]
  scope                            = azapi_resource.prometheus_workspace.id
  role_definition_name             = "Monitoring Data Reader"
  principal_id                     = local.grafana_principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "grafana_admin_user" {
  count                = var.user_object_id == "" ? 0 : 1
  scope                = azapi_resource.grafana.id
  role_definition_name = "Grafana Admin"
  principal_id         = var.user_object_id
}
