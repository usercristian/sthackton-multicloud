locals {
  microservices = toset([
    "donation-service",
    "ngo-service",
    "volunteer-service"
  ])
}

resource "oci_artifacts_container_repository" "services" {
  for_each = local.microservices

  compartment_id = var.compartment_ocid
  display_name   = "solidarytech/${each.value}"
  is_immutable   = false
  is_public      = false

  freeform_tags = var.tags
}