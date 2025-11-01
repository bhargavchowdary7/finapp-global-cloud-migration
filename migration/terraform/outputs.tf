# Resource Group Outputs
output "resource_group_name" {
  description = "The name of the resource group"
  value       = local.resource_group.name
}

output "resource_group_id" {
  description = "The ID of the resource group"
  value       = local.resource_group.id
}

output "resource_group_location" {
  description = "The location of the resource group"
  value       = local.resource_group.location
}

# Network Outputs
output "virtual_network_name" {
  description = "The name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "virtual_network_id" {
  description = "The ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "subnet_ids" {
  description = "The IDs of the subnets"
  value       = azurerm_subnet.subnets[*].id
}

output "network_security_group_id" {
  description = "The ID of the network security group"
  value       = azurerm_network_security_group.main.id
}

# Storage Outputs
output "storage_account_name" {
  description = "The name of the storage account"
  value       = azurerm_storage_account.migration.name
}

output "storage_account_id" {
  description = "The ID of the storage account"
  value       = azurerm_storage_account.migration.id
}

output "storage_account_primary_key" {
  description = "The primary access key for the storage account"
  value       = azurerm_storage_account.migration.primary_access_key
  sensitive   = true
}

output "storage_account_connection_string" {
  description = "The connection string for the storage account"
  value       = azurerm_storage_account.migration.primary_connection_string
  sensitive   = true
}

output "file_share_name" {
  description = "The name of the file share"
  value       = azurerm_storage_share.migration.name
}

output "file_share_url" {
  description = "The URL of the file share"
  value       = "${azurerm_storage_account.migration.primary_file_endpoint}${azurerm_storage_share.migration.name}"
}

output "storage_container_name" {
  description = "The name of the storage container for migration artifacts"
  value       = azurerm_storage_container.migration_artifacts.name
}

# Key Vault Outputs
output "key_vault_name" {
  description = "The name of the key vault"
  value       = var.create_key_vault ? azurerm_key_vault.main[0].name : ""
}

output "key_vault_id" {
  description = "The ID of the key vault"
  value       = var.create_key_vault ? azurerm_key_vault.main[0].id : ""
}

output "key_vault_uri" {
  description = "The URI of the key vault"
  value       = var.create_key_vault ? azurerm_key_vault.main[0].vault_uri : ""
}

# Storage Sync Outputs (if created)
output "storage_sync_name" {
  description = "The name of the storage sync service"
  value       = var.create_storage_sync ? azurerm_storage_sync.main[0].name : ""
}

output "storage_sync_id" {
  description = "The ID of the storage sync service"
  value       = var.create_storage_sync ? azurerm_storage_sync.main[0].id : ""
}

# Monitoring Outputs
output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : ""
}

output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : ""
}

output "application_insights_id" {
  description = "The ID of the Application Insights resource"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].id : ""
}

output "application_insights_app_id" {
  description = "The App ID of the Application Insights resource"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].app_id : ""
}

output "application_insights_instrumentation_key" {
  description = "The Instrumentation Key of the Application Insights resource"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : ""
  sensitive   = true
}

# Backup Outputs
output "backup_vault_name" {
  description = "The name of the backup vault"
  value       = var.enable_backup ? azurerm_data_protection_backup_vault.main[0].name : ""
}

output "backup_vault_id" {
  description = "The ID of the backup vault"
  value       = var.enable_backup ? azurerm_data_protection_backup_vault.main[0].id : ""
}

# Migration Configuration Outputs
output "migration_configuration" {
  description = "Configuration values needed for migration scripts"
  value = {
    storage_account_name = azurerm_storage_account.migration.name
    file_share_name      = azurerm_storage_share.migration.name
    resource_group       = local.resource_group.name
    location             = local.resource_group.location
    key_vault_name       = var.create_key_vault ? azurerm_key_vault.main[0].name : "Use existing Key Vault"
    postgresql_server = "Use PostgreSQL Flexible Server from infrastructure module"

  }
}

# Connection Information for Migration
output "migration_connection_info" {
  description = "Connection information for migration tools"
  value = {
    storage_connection_string = azurerm_storage_account.migration.primary_connection_string
    file_share_path          = "\\\\${azurerm_storage_account.migration.primary_file_host}\\${azurerm_storage_share.migration.name}"
    azcopy_target_url        = "${azurerm_storage_account.migration.primary_blob_endpoint}${azurerm_storage_container.migration_artifacts.name}"
  }
  sensitive = true
}

# Private Endpoint Outputs
output "private_endpoint_ip" {
  description = "The private IP address of the storage private endpoint"
  value       = var.enable_private_endpoints ? azurerm_private_endpoint.storage[0].private_service_connection[0].private_ip_address : ""
}

# Budget Output
output "budget_configured" {
  description = "Whether a budget was configured"
  value       = var.budget_amount > 0
}

output "budget_amount" {
  description = "The configured budget amount"
  value       = var.budget_amount
}

# Tags Output
output "common_tags" {
  description = "The common tags applied to all resources"
  value       = local.common_tags
}

# Random Suffix (for reference)
output "random_suffix" {
  description = "The random suffix used for unique resource naming"
  value       = random_string.suffix.result
}