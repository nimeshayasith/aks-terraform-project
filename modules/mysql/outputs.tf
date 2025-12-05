output "mysql_name" {
  value = azurerm_mysql_flexible_server.mysql.name
}

output "mysql_fqdn" {
  value = azurerm_mysql_flexible_server.mysql.fqdn
}

output "mysql_private_endpoint_id" {
  value = azurerm_private_endpoint.db_pe.id
}
