# DR SQL Servers in same region (for sovereignty)
resource "azurerm_mssql_server" "regional_dr" {
  for_each = var.regions

  name                         = "sql-${var.project}-${each.key}-dr"
  resource_group_name          = azurerm_resource_group.main[each.key].name
  location                     = each.value.region  # Same region for sovereignty
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password

  connection_policy = "Proxy"

  tags = merge(local.common_tags, {
    Region = each.key
    Role   = "dr"
  })
}

# Regional DR setup for each sovereign region
resource "azurerm_mssql_failover_group" "regional_dr" {
  for_each = var.regions

  name      = "fog-${var.project}-${each.key}"
  server_id = azurerm_mssql_server.regional_primary[each.key].id

  partner_server {
    id = azurerm_mssql_server.regional_dr[each.key].id
  }

  read_write_endpoint_failover_policy {
    mode          = "Automatic"
    grace_minutes = 5  # Meets RPO < 5 minutes
  }

  databases = [azurerm_mssql_database.regional_db[each.key].id]

  tags = merge(local.common_tags, {
    Region = each.key
  })
}