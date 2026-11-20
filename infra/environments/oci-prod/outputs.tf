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
  description = "Repositórios OCIR criados para os microsserviços"
  value       = module.oke.ocir_repositories
}