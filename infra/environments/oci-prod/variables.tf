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

variable "db_secret_id" {
  description = "OCID do secret no OCI Vault que contém a senha administrativa PostgreSQL"
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

variable "oke_node_ocpus" {
  description = "Quantidade de OCPUs por Worker Node do ambiente OCI de produção"
  type        = number
  default     = 2
}

variable "oke_node_memory_in_gbs" {
  description = "Memória RAM em GB por Worker Node do ambiente OCI de produção"
  type        = number
  default     = 12
}

variable "oke_fault_domains" {
  description = "Fault Domains permitidos para alocação dos Worker Nodes"
  type        = list(string)
  default     = ["FAULT-DOMAIN-1"]
}

variable "oke_admin_allowed_cidrs" {
  description = "CIDRs externos autorizados a acessar a API pública do OKE pela porta TCP/6443"
  type        = list(string)
  default     = []
}