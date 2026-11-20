data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

data "oci_containerengine_node_pool_option" "oke_options" {
  node_pool_option_id = oci_containerengine_cluster.main.id
  compartment_id      = var.compartment_ocid
}

locals {
  # Seleciona automaticamente a imagem Oracle Linux 8 ARM64 (aarch64) compatível com a versão do OKE
  arm64_images = [
    for s in data.oci_containerengine_node_pool_option.oke_options.sources : s.image_id
    if length(regexall("Oracle-Linux-8.*aarch64", s.source_name)) > 0
  ]
}

resource "oci_containerengine_node_pool" "arm64_pool" {
  cluster_id         = oci_containerengine_cluster.main.id
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.kubernetes_version
  name               = "solidarytech-arm64-pool"
  node_shape         = var.node_shape

  node_shape_config {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_in_gbs
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = local.arm64_images[0]
    boot_volume_size_in_gbs = 50
  }

  node_config_details {
    size = var.node_count

    dynamic "placement_configs" {
      for_each = data.oci_identity_availability_domains.ads.availability_domains
      content {
        availability_domain = placement_configs.value.name
        subnet_id           = var.private_oke_subnet_id
      }
    }

    freeform_tags = var.tags
  }

  initial_node_labels {
    key   = "arch"
    value = "arm64"
  }

  freeform_tags = var.tags
}