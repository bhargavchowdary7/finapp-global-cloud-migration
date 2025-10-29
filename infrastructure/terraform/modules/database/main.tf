# PostgreSQL Flexible Server - 50TB Database with HA for DR
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "pgsql-${replace(lower(var.region), " ", "")}-${random_id.suffix.hex}"
  resource_group_name    = var.resource_group
  location               = var.region
  version                = var.db_version
  administrator_login    = var.admin_username
  administrator_password = var.admin_password
  storage_mb             = var.storage_mb  # 50TB = 51200000 MB
  sku_name               = var.sku_name    # High-performance SKU for 50TB

  # Zone Redundant HA for DR requirements (RTO < 1h, RPO < 5min)
  high_availability {
    mode                      = "ZoneRedundant"
    standby_availability_zone = "2"
  }

  backup_retention_days  = var.backup_retention_days

  # Maintenance window during low traffic
  maintenance_window {
    day_of_week  = 0  # Sunday
    start_hour   = 2  # 2 AM
    start_minute = 0
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      zone,
      high_availability[0].standby_availability_zone
    ]
  }
}

# Private DNS Zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgresql" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group

  tags = var.tags
}

# Link Private DNS Zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "postgresql" {
  name                  = "pgsql-vnet-link-${random_id.suffix.hex}"
  private_dns_zone_name = azurerm_private_dns_zone.postgresql.name
  virtual_network_id    = split("/", var.subnet_id)[0]
  resource_group_name   = var.resource_group

  depends_on = [azurerm_private_dns_zone.postgresql]
}

# Private Endpoint for PostgreSQL - Security requirement
resource "azurerm_private_endpoint" "postgresql" {
  name                = "pe-pgsql-${random_id.suffix.hex}"
  resource_group_name = var.resource_group
  location            = var.region
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "pgsql-connection"
    private_connection_resource_id = azurerm_postgresql_flexible_server.main.id
    subresource_names              = ["postgresqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.postgresql.id]
  }

  tags = var.tags
}

# Transaction database for financial data
resource "azurerm_postgresql_flexible_server_database" "transaction_db" {
  name      = "financial_transactions"
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Random ID for unique naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Read replicas for sub-50ms latency
resource "azurerm_postgresql_flexible_server_replica" "read_replica" {
  # Add read replicas in each AZ
}
