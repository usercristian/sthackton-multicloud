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