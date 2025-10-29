output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  value       = azurerm_log_analytics_workspace.main.id
}

output "application_insights_id" {
  description = "Application Insights ID"
  value       = azurerm_application_insights.main.id
}

output "critical_action_group_id" {
  description = "Critical action group ID for alerts"
  value       = azurerm_monitor_action_group.critical.id
}

output "warning_action_group_id" {
  description = "Warning action group ID for alerts"
  value       = azurerm_monitor_action_group.warning.id
}