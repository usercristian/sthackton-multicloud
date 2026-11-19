locals {
  finops_tags = {
    Project     = "Solidary Tech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
    ManagedBy   = "Terraform-OCI"
  }
}

module "network" {
  source = "../../modules/oci/network"

  compartment_ocid = var.compartment_ocid
  tags             = local.finops_tags
}