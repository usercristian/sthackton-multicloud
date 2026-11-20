output "cluster_id" {
  description = "OCID do cluster OKE"
  value       = oci_containerengine_cluster.main.id
}

output "cluster_endpoint" {
  description = "Endpoint público da API do Kubernetes"
  value       = oci_containerengine_cluster.main.endpoints[0].kubernetes
}

output "node_pool_id" {
  description = "OCID do Node Pool ARM64"
  value       = oci_containerengine_node_pool.arm64_pool.id
}

output "ocir_repositories" {
  description = "Mapa dos repositórios OCIR criados por microsserviço"
  value       = { for k, repo in oci_artifacts_container_repository.services : k => repo.display_name }
}