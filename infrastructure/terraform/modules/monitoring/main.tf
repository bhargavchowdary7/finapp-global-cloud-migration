# Log Analytics Workspace for monitoring and diagnostics
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${replace(lower(var.region), " ", "")}-${random_id.suffix.hex}"
  location            = var.region
  resource_group_name = var.resource_group
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}

# Diagnostic Settings for PostgreSQL - Monitor for sub-50ms latency
resource "azurerm_monitor_diagnostic_setting" "postgresql" {
  name                       = "postgresql-diagnostics"
  target_resource_id         = var.postgresql_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "PostgreSQLLogs"
  }

  enabled_log {
    category = "AllMetrics"
  }

  # Retention is now managed by the log analytics workspace
}

# Diagnostic Settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage" {
  name                       = "storage-diagnostics"
  target_resource_id         = var.storage_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_log {
    category = "Transaction"
  }
}

# Alert for database CPU usage (monitoring performance)
resource "azurerm_monitor_metric_alert" "db_cpu" {
  name                = "db-cpu-alert-${random_id.suffix.hex}"
  resource_group_name = var.resource_group
  scopes              = [var.postgresql_id]
  description         = "Alert when database CPU usage is high"
  severity            = 2
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80  # Alert when CPU > 80%
  }

  window_size        = "PT5M"
  frequency          = "PT1M"
  auto_mitigate      = false

  action {
    action_group_id = azurerm_monitor_action_group.critical.id
  }

  tags = var.tags
}

# Alert for database memory usage
resource "azurerm_monitor_metric_alert" "db_memory" {
  name                = "db-memory-alert-${random_id.suffix.hex}"
  resource_group_name = var.resource_group
  scopes              = [var.postgresql_id]
  description         = "Alert when database memory usage is high"
  severity            = 2
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "memory_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85  # Alert when memory > 85%
  }

  window_size        = "PT5M"
  frequency          = "PT1M"
  auto_mitigate      = false

  action {
    action_group_id = azurerm_monitor_action_group.critical.id
  }

  tags = var.tags
}

# Alert for storage latency (sub-50ms requirement)
resource "azurerm_monitor_metric_alert" "storage_latency" {
  name                = "storage-latency-alert-${random_id.suffix.hex}"
  resource_group_name = var.resource_group
  scopes              = [var.storage_id]
  description         = "Alert when storage latency exceeds 50ms"
  severity            = 2
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts"
    metric_name      = "SuccessE2ELatency"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 50  # 50ms threshold as per requirement
  }

  window_size        = "PT5M"
  frequency          = "PT1M"
  auto_mitigate      = false

  action {
    action_group_id = azurerm_monitor_action_group.critical.id
  }

  tags = var.tags
}

# Alert for database storage usage (50TB monitoring)
resource "azurerm_monitor_metric_alert" "db_storage" {
  name                = "db-storage-alert-${random_id.suffix.hex}"
  resource_group_name = var.resource_group
  scopes              = [var.postgresql_id]
  description         = "Alert when database storage usage is high"
  severity            = 1
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "storage_used"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 45000000  # 45TB alert (90% of 50TB)
  }

  window_size        = "PT15M"
  frequency          = "PT5M"
  auto_mitigate      = false

  action {
    action_group_id = azurerm_monitor_action_group.warning.id
  }

  tags = var.tags
}

# Alert for storage capacity (100TB monitoring)
resource "azurerm_monitor_metric_alert" "storage_capacity" {
  name                = "storage-capacity-alert-${random_id.suffix.hex}"
  resource_group_name = var.resource_group
  scopes              = [var.storage_id]
  description         = "Alert when storage capacity is high"
  severity            = 1
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts"
    metric_name      = "UsedCapacity"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90000000000  # 90TB alert (90% of 100TB)
  }

  window_size        = "PT15M"
  frequency          = "PT5M"
  auto_mitigate      = false

  action {
    action_group_id = azurerm_monitor_action_group.warning.id
  }

  tags = var.tags
}

# Action Group for critical alerts
resource "azurerm_monitor_action_group" "critical" {
  name                = "critical-alerts-${random_id.suffix.hex}"
  resource_group_name = var.resource_group
  short_name          = "critical"

  email_receiver {
    name          = "admin"
    email_address = "admin@company.com"
  }

  tags = var.tags
}

# Action Group for warning alerts
resource "azurerm_monitor_action_group" "warning" {
  name                = "warning-alerts-${random_id.suffix.hex}"
  resource_group_name = var.resource_group
  short_name          = "warning"

  email_receiver {
    name          = "dba-team"
    email_address = "dba@company.com"
  }

  tags = var.tags
}

# Application Insights for application performance monitoring
resource "azurerm_application_insights" "main" {
  name                = "appi-${replace(lower(var.region), " ", "")}-${random_id.suffix.hex}"
  location            = var.region
  resource_group_name = var.resource_group
  application_type    = "web"
  retention_in_days   = 30

  tags = var.tags
}

# Random ID for unique naming
resource "random_id" "suffix" {
  byte_length = 4
}