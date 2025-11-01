# Azure Credentials
# These values should be set as environment variables or in a secure manner
# subscription_id = "00000000-0000-0000-0000-000000000000"
# client_id       = "00000000-0000-0000-0000-000000000000"
# client_secret   = "client-secret"
# tenant_id       = "00000000-0000-0000-0000-000000000000"

# Project Configuration
project_name = "storagemigration"
environment  = "dev"
location     = "East US"

# Resource Group
create_resource_group = true
resource_group_name   = ""

# Network Configuration
vnet_address_space       = ["10.0.0.0/19"]
subnet_address_prefixes  = ["10.0.1.0/24", "10.0.2.0/24"]

# Storage Configuration
storage_account_tier              = "Standard"
storage_account_replication_type  = "LRS"
file_share_quota_gb               = 5120
create_storage_sync               = false

# Database Configuration
create_sql_server    = false
sql_admin_username   = "sqladmin"
sql_admin_password   = "ChangeMe123!" # Change this in production

# Key Vault Configuration
create_key_vault = true
key_vault_sku    = "standard"

# Monitoring
enable_monitoring = true

# Security
enable_private_endpoints = false

# Backup
enable_backup = false

# Budget
budget_amount = 1000

# Tags
tags = {
  Project     = "StorageMigration"
  Environment = "dev"
  ManagedBy   = "Terraform"
  Department  = "IT"
  CostCenter  = "12345"
}