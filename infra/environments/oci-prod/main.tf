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

module "oke" {
  source = "../../modules/oci/oke"

  compartment_ocid      = var.compartment_ocid
  vcn_id                = module.network.vcn_id
  public_lb_subnet_id   = module.network.public_lb_subnet_id
  private_oke_subnet_id = module.network.private_oke_subnet_id
  tags                  = local.finops_tags
}