environment = "Production"
project = "FinApp"
cost_center = "9876"

# Regions as specified in PDF: North America, Europe (UK), Asia (Singapore)
regions = {
  north-america = {
    region           = "East US 2"  # North America region
    db_sku_name      = "GP_Standard_D16s_v3"  # For 50TB database performance
    db_storage_mb    = 51200000  # 50 TB = 50 * 1024 * 1024 MB
    db_version       = "13"
    storage_account_tier = "Standard"  # For 100TB transaction logs storage
    storage_replication_type = "ZRS"
    enable_geo_backup = true  # For production DR
  }
  europe = {
    region           = "UK South"  # Europe (UK) region as per PDF
    db_sku_name      = "GP_Standard_D16s_v3"
    db_storage_mb    = 51200000  # 50 TB
    db_version       = "13"
    storage_account_tier = "Standard"
    storage_replication_type = "ZRS"
    enable_geo_backup = true  # For production DR
  }
  asia = {
    region           = "Southeast Asia"  # Asia (Singapore) region as per PDF
    db_sku_name      = "GP_Standard_D16s_v3"
    db_storage_mb    = 51200000  # 50 TB
    db_version       = "13"
    storage_account_tier = "Standard"
    storage_replication_type = "ZRS"
    enable_geo_backup = true  # For production DR
  }
}


existing_vnet_name = "finapp-vnet"
existing_subnet_name = "private-endpoints"
admin_username = "finappadmin"
backup_retention_days = 30 # for 7 days retention free of cost, but it was trading platform so increased to 30 days.
lifecycle_cool_tier_days = 90
lifecycle_archive_tier_days = 365