output "vcn_id" {
  description = "OCID da VCN principal"
  value       = oci_core_vcn.main.id
}

output "public_lb_subnet_id" {
  description = "OCID da sub-rede pública para Load Balancers"
  value       = oci_core_subnet.public_lb.id
}

output "private_oke_subnet_id" {
  description = "OCID da sub-rede privada dos Worker Nodes OKE"
  value       = oci_core_subnet.private_oke.id
}

output "private_db_subnet_id" {
  description = "OCID da sub-rede privada do PostgreSQL"
  value       = oci_core_subnet.private_db.id
}