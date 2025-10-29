output "region_deployments" {
  description = "Details of deployments in each region"
  value = {
    for region, config in var.regions : region => {
      resource_group    = azurerm_resource_group.main[region].name
      location          = azurerm_resource_group.main[region].location
      postgresql_fqdn   = module.database[region].postgresql_fqdn
      postgresql_name   = module.database[region].postgresql_name
      storage_account   = module.storage[region].storage_account_name
      key_vault_name    = azurerm_key_vault.main[region].name
      private_endpoints = {
        postgresql = module.database[region].private_endpoint_id
        storage    = module.storage[region].private_endpoint_id
      }
    }
  }
}

output "database_connection_strings" {
  description = "Database connection strings (without password)"
  value = {
    for region, config in var.regions : region => "Host=${module.database[region].postgresql_fqdn};Database=${module.database[region].database_name};Username=${var.admin_username}"
  }
  sensitive = true
}

output "key_vault_secrets" {
  description = "Key Vault secret references"
  value = {
    for region, config in var.regions : region => {
      postgresql_password = azurerm_key_vault_secret.postgresql_password[region].id
    }
  }
}

output "storage_container_names" {
  description = "Storage container names"
  value = {
    for region, config in var.regions : region => {
      active  = module.storage[region].active_container_name
      archive = module.storage[region].archive_container_name
    }
  }
}