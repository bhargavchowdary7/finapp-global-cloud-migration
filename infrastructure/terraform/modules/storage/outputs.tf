output "storage_account_id" {
  description = "Storage account ID"
  value       = azurerm_storage_account.main.id
}

output "storage_account_name" {
  description = "Storage account name"
  value       = azurerm_storage_account.main.name
}

output "private_endpoint_id" {
  description = "Private endpoint ID for storage"
  value       = azurerm_private_endpoint.blob.id
}

output "file_share_names" {
  description = "File share names"
  value = {
    transaction_logs = azurerm_storage_share.transaction_logs.name
    archive_logs     = azurerm_storage_share.archive_logs.name
  }
}

output "container_names" {
  description = "Container names"
  value = {
    active  = azurerm_storage_container.active.name
    archive = azurerm_storage_container.archive.name
  }
}