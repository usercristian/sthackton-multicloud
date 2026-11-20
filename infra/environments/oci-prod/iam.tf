resource "oci_identity_policy" "oke_service_policy" {
  compartment_id = var.tenancy_ocid
  name           = "solidarytech-oke-service-policy"
  description    = "Permite que o serviço OKE provisione e gerencie Worker Nodes, VNICs e volumes no compartment do projeto"

  statements = [
    "Allow service OKE to manage instance-family in compartment id ${var.compartment_ocid}",
    "Allow service OKE to use virtual-network-family in compartment id ${var.compartment_ocid}",
    "Allow service OKE to manage volume-family in compartment id ${var.compartment_ocid}"
  ]

  freeform_tags = local.finops_tags
}