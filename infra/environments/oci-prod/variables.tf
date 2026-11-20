variable "tenancy_ocid" {
  description = "OCID da Tenancy na Oracle Cloud"
  type        = string
}

variable "user_ocid" {
  description = "OCID do usuário IAM"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint da chave API"
  type        = string
}

variable "private_key_path" {
  description = "Caminho temporário da chave privada API no runner"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID do Compartment da SolidaryTech"
  type        = string
}

variable "region" {
  description = "Região principal da OCI"
  type        = string
  default     = "sa-saopaulo-1"
}

variable "oke_node_shape" {
  description = "Shape ARM64 dos Worker Nodes do OKE"
  type        = string
  default     = "VM.Standard.A2.Flex"
}

variable "oke_node_count" {
  description = "Quantidade de Worker Nodes no Node Pool"
  type        = number
  default     = 1
}

variable "oke_fault_domains" {
  description = "Fault Domains permitidos para alocação dos Worker Nodes"
  type        = list(string)
  default     = ["FAULT-DOMAIN-1"]
}