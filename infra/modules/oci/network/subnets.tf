resource "oci_core_subnet" "public_lb" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.public_subnet_cidr
  display_name               = "solidarytech-subnet-public-lb"
  dns_label                  = "subpublb"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public_lb.id]
  prohibit_public_ip_on_vnic = false
  freeform_tags              = var.tags
}

resource "oci_core_subnet" "private_oke" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.private_oke_subnet_cidr
  display_name               = "solidarytech-subnet-private-oke"
  dns_label                  = "subprivoke"
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private_oke.id]
  prohibit_public_ip_on_vnic = true
  freeform_tags              = var.tags
}

resource "oci_core_subnet" "private_db" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.private_db_subnet_cidr
  display_name               = "solidarytech-subnet-private-db"
  dns_label                  = "subprivdb"
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private_db.id]
  prohibit_public_ip_on_vnic = true
  freeform_tags              = var.tags
}