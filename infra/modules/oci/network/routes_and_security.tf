# --- TABELAS DE ROTEAMENTO ---

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "solidarytech-rt-public"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }

  freeform_tags = var.tags
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "solidarytech-rt-private"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.nat.id
  }

  route_rules {
    destination       = data.oci_core_services.all_oci_services.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.sgw.id
  }

  freeform_tags = var.tags
}

# --- SECURITY LISTS ---

resource "oci_core_security_list" "public_lb" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "solidarytech-sl-public-lb"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 443
      max = 443
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = var.private_oke_subnet_cidr
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  dynamic "ingress_security_rules" {
    for_each = var.admin_allowed_cidrs
    content {
      protocol  = "6"
      source    = ingress_security_rules.value
      stateless = false

      tcp_options {
        min = 6443
        max = 6443
      }
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = var.private_oke_subnet_cidr
    tcp_options {
      min = 12250
      max = 12250
    }
  }

  ingress_security_rules {
    protocol = "1"
    source   = var.private_oke_subnet_cidr
    icmp_options {
      type = 3
      code = 4
    }
  }

  freeform_tags = var.tags
}

resource "oci_core_security_list" "private_oke" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "solidarytech-sl-private-oke"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    protocol = "all"
    source   = var.vcn_cidr
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  freeform_tags = var.tags
}

resource "oci_core_security_list" "private_db" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "solidarytech-sl-private-db"

  egress_security_rules {
    destination = var.vcn_cidr
    protocol    = "all"
  }

  ingress_security_rules {
    protocol = "6"
    source   = var.private_oke_subnet_cidr
    tcp_options {
      min = 5432
      max = 5432
    }
  }

  freeform_tags = var.tags
}