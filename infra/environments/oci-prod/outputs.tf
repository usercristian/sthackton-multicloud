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