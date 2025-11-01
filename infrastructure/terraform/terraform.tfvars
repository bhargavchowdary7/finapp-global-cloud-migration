environment = "Production"
project = "FinApp"
cost_center = "9876"

# Regions as specified : North America, Europe (UK), Asia (Singapore)
regions = {
  north-america = {
    region           = "East US 2"
    db_sku_name      = "GP_Standard_D16ds_v4"  #  v4 supports Premium SSD v2
    db_storage_mb = 52428800  # 50TB in megabytes
    db_storage_tier  = "P80"   #  Premium SSD v2 tier
    db_version       = "16"    #  Use PostgreSQL 16 (latest stable)
    storage_account_tier = "Premium"
    storage_replication_type = "ZRS"
  }
  europe = {
    region           = "UK South"
    db_sku_name      = "GP_Standard_D16ds_v4"
    db_storage_mb    = 52428800  # 50 TB
    db_storage_tier  = "P80"
    db_version       = "16"
    storage_account_tier = "Premium"
    storage_replication_type = "ZRS"
  }
  asia = {
    region           = "Southeast Asia"
    db_sku_name      = "GP_Standard_D16ds_v4"
    db_storage_mb    = 52428800  # 50 TB
    db_storage_tier  = "P80"
    db_version       = "16"
    storage_account_tier = "Premium"
    storage_replication_type = "ZRS"
  }
}



existing_vnet_name = "finapp-vnet"
existing_subnet_name = "private-endpoints"
admin_username = "finappadmin"
backup_retention_days = 30 # for 7 days retention free of cost, but it was trading platform so increased to 30 days.
lifecycle_cool_tier_days = 90
lifecycle_archive_tier_days = 365



# Option 1: Provide password directly (less secure)
# sql_admin_username = "finappadmin"
# sql_admin_password = "YourSecurePassword123!"

# Option 2: Remove password from tfvars and use environment variables
sql_admin_username = "finappadmin"
# sql_admin_password will be auto-generated and stored in Key Vault