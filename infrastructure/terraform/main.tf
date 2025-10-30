# Generate random password for PostgreSQL
resource "random_password" "postgresql_password" {
  length           = 16
  special          = true
  override_special = "!_%@"
}

# Common tags
locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project
    CostCenter  = var.cost_center
    ManagedBy   = "Terraform"
  }
}

# Create Resource Groups for each region
resource "azurerm_resource_group" "main" {
  for_each = var.regions

  name     = "rg-${var.project}-${each.key}-${var.environment}"
  location = each.value.region

  tags = merge(local.common_tags, {
    Region = each.key
  })
}

# Create Key Vault for each region for secrets management
resource "azurerm_key_vault" "main" {
  for_each = var.regions

  name                        = "kv-${var.project}-${each.key}-${random_id.suffix[each.key].hex}"
  location                    = azurerm_resource_group.main[each.key].location
  resource_group_name         = azurerm_resource_group.main[each.key].name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "premium"
  enabled_for_disk_encryption = true
  purge_protection_enabled    = true

  tags = merge(local.common_tags, {
    Region = each.key
  })
}

# Store PostgreSQL password in Key Vault
resource "azurerm_key_vault_secret" "postgresql_password" {
  for_each = var.regions

  name         = "postgresql-admin-password"
  value        = random_password.postgresql_password.result
  key_vault_id = azurerm_key_vault.main[each.key].id

  depends_on = [azurerm_key_vault_access_policy.current_user]
}

# Key Vault access policy for current user
resource "azurerm_key_vault_access_policy" "current_user" {
  for_each = var.regions

  key_vault_id = azurerm_key_vault.main[each.key].id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"
  ]
}

# Regional SQL Databases for data sovereignty - Primary
resource "azurerm_mssql_server" "regional_primary" {
  for_each = var.regions

  name                         = "sql-${var.project}-${each.key}-primary"
  resource_group_name          = azurerm_resource_group.main[each.key].name
  location                     = each.value.region
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password

  # Critical for data sovereignty - restrict public access
  connection_policy = "Proxy"  # More restrictive than Default

  tags = merge(local.common_tags, {
    Region = each.key
    Role   = "primary"
  })
}

resource "azurerm_mssql_database" "regional_db" {
  for_each = var.regions

  name           = "sqldb-${var.project}-${each.key}"
  server_id      = azurerm_mssql_server.regional_primary[each.key].id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  max_size_gb    = 51200  # 50 TB capacity
  sku_name       = "BC_Gen5_16"  # Business Critical for <50ms latency

  # Geo-backup disabled to prevent cross-region data transfer for sovereignty
  geo_backup_enabled = false

  tags = merge(local.common_tags, {
    Region = each.key
  })
}

# Random ID suffix for unique naming
resource "random_id" "suffix" {
  for_each = var.regions

  byte_length = 4
}

# Get existing VNet data
data "azurerm_virtual_network" "existing" {
  for_each = var.regions

  name                = var.existing_vnet_name
  resource_group_name = azurerm_resource_group.main[each.key].name
}

data "azurerm_subnet" "existing" {
  for_each = var.regions

  name                 = var.existing_subnet_name
  virtual_network_name = data.azurerm_virtual_network.existing[each.key].name
  resource_group_name  = azurerm_resource_group.main[each.key].name
}

data "azurerm_client_config" "current" {}

# Call modules for each region - DATA SOVEREIGNTY: No cross-region replication
module "database" {
  for_each = var.regions

  source = "./modules/database"

  region          = each.value.region
  resource_group  = azurerm_resource_group.main[each.key].name
  sku_name        = each.value.db_sku_name
  storage_mb      = each.value.db_storage_mb  # 50TB
  db_version      = each.value.db_version
  admin_username  = var.admin_username
  admin_password  = random_password.postgresql_password.result
  backup_retention_days = var.backup_retention_days
  subnet_id       = data.azurerm_subnet.existing[each.key].id
  
  tags = merge(local.common_tags, {
    Region = each.key
  })
}

module "storage" {
  for_each = var.regions

  source = "./modules/storage"

  region          = each.value.region
  resource_group  = azurerm_resource_group.main[each.key].name
  account_tier    = each.value.storage_account_tier
  replication_type = each.value.storage_replication_type
  subnet_id       = data.azurerm_subnet.existing[each.key].id
  cool_tier_days  = var.lifecycle_cool_tier_days
  archive_tier_days = var.lifecycle_archive_tier_days
  
  tags = merge(local.common_tags, {
    Region = each.key
  })
}

module "monitoring" {
  for_each = var.regions

  source = "./modules/monitoring"

  region         = each.value.region
  resource_group = azurerm_resource_group.main[each.key].name
  postgresql_id  = module.database[each.key].postgresql_id
  storage_id     = module.storage[each.key].storage_account_id
  
  tags = merge(local.common_tags, {
    Region = each.key
  })
}