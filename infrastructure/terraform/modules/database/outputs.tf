output "postgresql_id" {
  description = "PostgreSQL server ID"
  value       = azurerm_postgresql_flexible_server.main.id
}

output "postgresql_fqdn" {
  description = "PostgreSQL fully qualified domain name"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "postgresql_name" {
  description = "PostgreSQL server name"
  value       = azurerm_postgresql_flexible_server.main.name
}

output "private_endpoint_id" {
  description = "Private endpoint ID for PostgreSQL"
  value       = azurerm_private_endpoint.postgresql.id
}

output "database_name" {
  description = "Transaction database name"
  value       = azurerm_postgresql_flexible_server_database.transaction_db.name
}

output "read_replica_az2_fqdn" {
  value = azurerm_postgresql_flexible_server_replica.read_replica_az2.fqdn
  description = "FQDN of read replica in AZ2"
}

output "read_replica_az3_fqdn" {
  value = azurerm_postgresql_flexible_server_replica.read_replica_az3.fqdn
  description = "FQDN of read replica in AZ3"
}
