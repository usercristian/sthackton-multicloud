output "db_system_id" {
  description = "OCID do sistema PostgreSQL"
  value       = oci_psql_db_system.main.id
}

output "private_endpoint_ip" {
  description = "Endereço IP privado do endpoint PostgreSQL"
  value       = oci_psql_db_system.main.network_details[0].primary_db_endpoint_private_ip
}

output "db_port" {
  description = "Porta de conexão do PostgreSQL"
  value       = 5432
}

output "admin_username" {
  description = "Nome do usuário administrador PostgreSQL"
  value       = var.admin_username
}
