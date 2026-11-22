removed {
  from = oci_artifacts_container_repository.services

  lifecycle {
    destroy = false
  }
}