# Enhanced Storage Account with disabled public access
resource "azurerm_storage_account" "main" {
  name                     = "st${replace(lower(var.region), " ", "")}${random_id.suffix.hex}"
  resource_group_name      = var.resource_group
  location                 = var.region
  account_tier             = var.account_tier
  account_replication_type = "GRS"
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"
  
  # For transaction logs - Hot tier for active, Cool for archives
  access_tier              = "Hot"

  # CRITICAL: Disable public network access for data sovereignty
  public_network_access_enabled = false

  # Large scale storage for 100TB
  large_file_share_enabled = true

  # Enable blob versioning for RPO compliance and lifecycle management
  blob_properties {
    versioning_enabled = true
    change_feed_enabled = true
    
    container_delete_retention_policy {
      days = 7
    }
    
    delete_retention_policy {
      days = 365
    }
  }

  tags = var.tags
}

# ADD THESE CONTAINERS FOR THE REQUIREMENTS
resource "azurerm_storage_container" "dept_files_active" {
  name                  = "dept-files-active"
  storage_account_id    = azurerm_storage_account.main.id  # Use storage_account_id instead
  container_access_type = "private"
}

resource "azurerm_storage_container" "dept_files_archive" {
  name                  = "dept-files-archive"
  storage_account_id    = azurerm_storage_account.main.id  # Use storage_account_id instead
  container_access_type = "private"
}

# File Shares for NAS-like storage (replacing on-prem NAS)
resource "azurerm_storage_share" "transaction_logs" {
  name                 = "transaction-logs"
  storage_account_id   = azurerm_storage_account.main.id
  quota                = 51200  # 50 TB for active transaction logs
  
  # Enable large file share support
  enabled_protocol = "SMB"
}

resource "azurerm_storage_share" "archive_logs" {
  name                 = "archive-logs"
  storage_account_id   = azurerm_storage_account.main.id
  quota                = 51200  # 50 TB for archive logs
  
  enabled_protocol = "SMB"
}

# Blob containers for additional storage options
resource "azurerm_storage_container" "active" {
  name                 = "txn-logs-active"
  storage_account_id   = azurerm_storage_account.main.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "archive" {
  name                 = "txn-logs-archive"
  storage_account_id   = azurerm_storage_account.main.id
  container_access_type = "private"
}

# Private DNS Zone for Blob Storage
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group

  tags = var.tags
}

# Private DNS Zone for File Storage
resource "azurerm_private_dns_zone" "file" {
  name                = "privatelink.file.core.windows.net"
  resource_group_name = var.resource_group

  tags = var.tags
}

# Link Private DNS Zones to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "blob-vnet-link-${random_id.suffix.hex}"
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = split("/", var.subnet_id)[0]
  resource_group_name   = var.resource_group
}

resource "azurerm_private_dns_zone_virtual_network_link" "file" {
  name                  = "file-vnet-link-${random_id.suffix.hex}"
  private_dns_zone_name = azurerm_private_dns_zone.file.name
  virtual_network_id    = split("/", var.subnet_id)[0]
  resource_group_name   = var.resource_group
}

# Private Endpoint for Blob Storage
resource "azurerm_private_endpoint" "blob" {
  name                = "pe-blob-${random_id.suffix.hex}"
  resource_group_name = var.resource_group
  location            = var.region
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "blob-connection"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }

  tags = var.tags
}

# Private Endpoint for File Storage
resource "azurerm_private_endpoint" "file" {
  name                = "pe-file-${random_id.suffix.hex}"
  resource_group_name = var.resource_group
  location            = var.region
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "file-connection"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.file.id]
  }

  tags = var.tags
}

# UPDATED Lifecycle Management Policy for cost optimization
resource "azurerm_storage_management_policy" "main" {
  storage_account_id = azurerm_storage_account.main.id

  # Rule for dept-files-active container ( Requirement)
  rule {
    name    = "DeptFilesActiveToCool"
    enabled = true
    filters {
      prefix_match = ["dept-files-active/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = var.lifecycle_cool_tier_days
        tier_to_archive_after_days_since_modification_greater_than = var.lifecycle_archive_tier_days
      }
    }
  }

  # Rule for active transaction logs - move to cool after 90 days
  rule {
    name    = "ActiveLogsToCool"
    enabled = true
    filters {
      prefix_match = ["txn-logs-active/", "transaction-logs/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = var.lifecycle_cool_tier_days
      }
    }
  }

  # Rule for archive logs - move to archive after 365 days
  rule {
    name    = "CoolToArchive"
    enabled = true
    filters {
      prefix_match = ["txn-logs-archive/", "archive-logs/", "dept-files-archive/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_archive_after_days_since_modification_greater_than = var.lifecycle_archive_tier_days
      }
    }
  }
}

# Random ID for unique naming
resource "random_id" "suffix" {
  byte_length = 4
}