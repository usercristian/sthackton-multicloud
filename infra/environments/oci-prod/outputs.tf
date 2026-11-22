output "vcn_id" {
  description = "OCID da VCN criada"
  value       = module.network.vcn_id
}

output "public_lb_subnet_id" {
  description = "OCID da sub-rede pública"
  value       = module.network.public_lb_subnet_id
}

output "private_oke_subnet_id" {
  description = "OCID da sub-rede privada do OKE"
  value       = module.network.private_oke_subnet_id
}

output "private_db_subnet_id" {
  description = "OCID da sub-rede privada do PostgreSQL"
  value       = module.network.private_db_subnet_id
}

output "oke_cluster_id" {
  description = "OCID do cluster OKE"
  value       = module.oke.cluster_id
}

output "oke_cluster_endpoint" {
  description = "Endpoint público da API do Kubernetes"
  value       = module.oke.cluster_endpoint
}

output "ocir_repositories" {
  description = "Nomes dos repositórios OCIR usados pelos microsserviços"
  value       = module.oke.ocir_repositories
}

output "postgres_db_system_id" {
  description = "OCID do sistema PostgreSQL"
  value       = module.postgres.db_system_id
}

output "postgres_private_ip" {
  description = "Endereço IP privado do endpoint PostgreSQL"
  value       = module.postgres.private_endpoint_ip
}

output "postgres_admin_username" {
  description = "Nome do usuário administrador PostgreSQL"
  value       = module.postgres.admin_username
}
