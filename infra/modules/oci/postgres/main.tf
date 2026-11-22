data "oci_identity_availability_domains" "regional" {
  compartment_id = var.compartment_ocid
}

resource "oci_psql_db_system" "main" {
  compartment_id              = var.compartment_ocid
  db_version                  = var.db_version
  display_name                = "solidarytech-postgres-prod"
  instance_count              = var.instance_count
  instance_memory_size_in_gbs = var.memory_in_gbs
  instance_ocpu_count         = var.ocpus
  shape                       = var.shape

  credentials {
    username = var.admin_username

    password_details {
      password_type  = "VAULT_SECRET"
      secret_id      = var.db_secret_id
      secret_version = 1
    }
  }

  network_details {
    subnet_id = var.private_db_subnet_id
  }

  storage_details {
    availability_domain   = data.oci_identity_availability_domains.regional.availability_domains[0].name
    is_regionally_durable = false
    iops                  = var.storage_iops
    system_type           = "OCI_OPTIMIZED_STORAGE"
  }

  system_type = "OCI_OPTIMIZED_STORAGE"

  management_policy {
    backup_policy {
      kind = "NONE"
    }
  }

  freeform_tags = var.tags
}
