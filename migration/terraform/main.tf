# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  name_suffix = "${var.project_name}-${var.environment}-${random_string.suffix.result}"
  base_name   = "${var.project_name}-${var.environment}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  count    = var.create_resource_group ? 1 : 0
  name     = coalesce(var.resource_group_name, "rg-${local.base_name}")
  location = var.location
  tags     = local.common_tags
}

data "azurerm_resource_group" "main" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

locals {
  resource_group = var.create_resource_group ? azurerm_resource_group.main[0] : data.azurerm_resource_group.main[0]
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${local.base_name}"
  resource_group_name = local.resource_group.name
  location            = local.resource_group.location
  address_space       = var.vnet_address_space
  tags                = local.common_tags
}

# Subnets
resource "azurerm_subnet" "subnets" {
  count                = length(var.subnet_address_prefixes)
  name                 = "snet-${local.base_name}-${count.index + 1}"
  resource_group_name  = local.resource_group.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address_prefixes[count.index]]
}

# Network Security Group
resource "azurerm_network_security_group" "main" {
  name                = "nsg-${local.base_name}"
  resource_group_name = local.resource_group.name
  location            = local.resource_group.location
  tags                = local.common_tags

  security_rule {
    name                       = "AllowRDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate NSG with Subnets
resource "azurerm_subnet_network_security_group_association" "main" {
  count                     = length(azurerm_subnet.subnets)
  subnet_id                 = azurerm_subnet.subnets[count.index].id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Storage Account for Migration
resource "azurerm_storage_account" "migration" {
  name                     = "st${replace(local.base_name, "-", "")}${random_string.suffix.result}"
  resource_group_name      = local.resource_group.name
  location                 = local.resource_group.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  min_tls_version          = "TLS1_2"

  # Enable required services
  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  network_rules {
    default_action             = "Allow"
    ip_rules                   = []
    virtual_network_subnet_ids = []
  }

  tags = local.common_tags
}

# File Share for migrated data - FIXED: Use storage_account_id instead of storage_account_name
resource "azurerm_storage_share" "migration" {
  name                 = "migration-share"
  storage_account_id   = azurerm_storage_account.migration.id
  quota                = var.file_share_quota_gb
}

# Container for migration logs and artifacts - FIXED: Use storage_account_id instead of storage_account_name
resource "azurerm_storage_container" "migration_artifacts" {
  name                  = "migration-artifacts"
  storage_account_id    = azurerm_storage_account.migration.id
  container_access_type = "private"
}

# Key Vault for secrets management - FIXED: Remove enable_rbac_authorization
resource "azurerm_key_vault" "main" {
  count                       = var.create_key_vault ? 1 : 0
  name                        = "kv-${local.base_name}-${random_string.suffix.result}"
  resource_group_name         = local.resource_group.name
  location                    = local.resource_group.location
  sku_name                    = var.key_vault_sku
  tenant_id                   = var.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = local.common_tags
}

# Key Vault Access Policies (using RBAC instead of classic policies)
resource "azurerm_role_assignment" "key_vault_secrets_officer" {
  count                = var.create_key_vault ? 1 : 0
  scope                = azurerm_key_vault.main[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.client_id
}

# Store SQL credentials in Key Vault (if SQL Server is created)
resource "azurerm_key_vault_secret" "sql_admin_username" {
  count        = var.create_key_vault && var.create_sql_server ? 1 : 0
  name         = "sql-admin-username"
  value        = var.sql_admin_username
  key_vault_id = azurerm_key_vault.main[0].id

  depends_on = [azurerm_role_assignment.key_vault_secrets_officer]
}

resource "azurerm_key_vault_secret" "sql_admin_password" {
  count        = var.create_key_vault && var.create_sql_server ? 1 : 0
  name         = "sql-admin-password"
  value        = var.sql_admin_password
  key_vault_id = azurerm_key_vault.main[0].id

  depends_on = [azurerm_role_assignment.key_vault_secrets_officer]
}

# SQL Server (if required for database migration)
resource "azurerm_mssql_server" "main" {
  count                        = var.create_sql_server ? 1 : 0
  name                         = "sql-${local.base_name}-${random_string.suffix.result}"
  resource_group_name          = local.resource_group.name
  location                     = local.resource_group.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password

  azuread_administrator {
    login_username = "AzureAD Admin"
    object_id      = var.tenant_id
  }

  tags = local.common_tags
}

# SQL Database
resource "azurerm_mssql_database" "main" {
  count       = var.create_sql_server ? 1 : 0
  name        = "sqldb-${local.base_name}"
  server_id   = azurerm_mssql_server.main[0].id
  sku_name    = "Basic"
  max_size_gb = 2

  tags = local.common_tags
}

# Storage Sync Service (for Azure File Sync)
resource "azurerm_storage_sync" "main" {
  count               = var.create_storage_sync ? 1 : 0
  name                = "sync-${local.base_name}"
  resource_group_name = local.resource_group.name
  location            = local.resource_group.location
  tags                = local.common_tags
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "log-${local.base_name}-${random_string.suffix.result}"
  resource_group_name = local.resource_group.name
  location            = local.resource_group.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "appi-${local.base_name}-${random_string.suffix.result}"
  resource_group_name = local.resource_group.name
  location            = local.resource_group.location
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  tags                = local.common_tags
}

# Action Group for alerts
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "ag-${local.base_name}"
  resource_group_name = local.resource_group.name
  short_name          = "migalert"

  email_receiver {
    name          = "admin"
    email_address = "admin@example.com" # Replace with actual email
  }

  tags = local.common_tags
}

# Budget Alert
resource "azurerm_consumption_budget_resource_group" "main" {
  count              = var.budget_amount > 0 ? 1 : 0
  name               = "budget-${local.base_name}"
  resource_group_id  = local.resource_group.id
  amount             = var.budget_amount
  time_grain         = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }

  notification {
    enabled        = true
    threshold      = 80.0
    operator       = "GreaterThan"
    threshold_type = "Actual"

    contact_emails = [
      "admin@example.com", # Replace with actual email
    ]
  }

  notification {
    enabled        = true
    threshold      = 100.0
    operator       = "GreaterThan"
    threshold_type = "Actual"

    contact_emails = [
      "admin@example.com", # Replace with actual email
    ]
  }
}

# Private Endpoints (if enabled)
resource "azurerm_private_endpoint" "storage" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-${azurerm_storage_account.migration.name}"
  resource_group_name = local.resource_group.name
  location            = local.resource_group.location
  subnet_id           = azurerm_subnet.subnets[0].id

  private_service_connection {
    name                           = "psc-storage"
    private_connection_resource_id = azurerm_storage_account.migration.id
    is_manual_connection           = false
    subresource_names              = ["file"]
  }

  tags = local.common_tags
}

# Backup Vault (if backup enabled)
resource "azurerm_data_protection_backup_vault" "main" {
  count               = var.enable_backup ? 1 : 0
  name                = "backupvault-${local.base_name}"
  resource_group_name = local.resource_group.name
  location            = local.resource_group.location
  datastore_type      = "VaultStore"
  redundancy          = "LocallyRedundant"

  tags = local.common_tags
}

# Backup Policy for File Share - FIXED: Add data_store_type
resource "azurerm_data_protection_backup_policy_blob_storage" "fileshare" {
  count    = var.enable_backup ? 1 : 0
  name     = "backuppolicy-fileshare"
  vault_id = azurerm_data_protection_backup_vault.main[0].id

  retention_rule {
    name     = "default"
    priority = 1

    criteria {
      absolute_criteria = "FirstOfDay"
    }

    life_cycle {
      duration        = "P30D"
      data_store_type = "OperationalStore"
    }
  }
}

# Backup Instance for File Share - FIXED: Remove invalid blob_storage_name attribute
resource "azurerm_data_protection_backup_instance_blob_storage" "fileshare" {
  count               = var.enable_backup ? 1 : 0
  name                = "backupinstance-${azurerm_storage_share.migration.name}"
  vault_id            = azurerm_data_protection_backup_vault.main[0].id
  location            = local.resource_group.location
  storage_account_id  = azurerm_storage_account.migration.id
  backup_policy_id    = azurerm_data_protection_backup_policy_blob_storage.fileshare[0].id

  depends_on = [azurerm_storage_share.migration]
}