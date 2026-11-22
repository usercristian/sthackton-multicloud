variable "compartment_ocid" {
  description = "OCID do Compartment onde o sistema PostgreSQL será criado"
  type        = string
}

variable "private_db_subnet_id" {
  description = "OCID da sub-rede privada do sistema PostgreSQL"
  type        = string
}

variable "db_secret_id" {
  description = "OCID do secret no OCI Vault que contém a senha administrativa"
  type        = string
}

variable "db_version" {
  description = "Versão principal do PostgreSQL"
  type        = string
  default     = "15"
}

variable "shape" {
  description = "Shape das instâncias PostgreSQL"
  type        = string
  default     = "PostgreSQL.VM.Standard.E5.Flex"
}

variable "ocpus" {
  description = "Quantidade de OCPUs por instância"
  type        = number
  default     = 1
}

variable "memory_in_gbs" {
  description = "Memória em GB por instância"
  type        = number
  default     = 16
}

variable "instance_count" {
  description = "Quantidade de instâncias PostgreSQL"
  type        = number
  default     = 1
}

variable "storage_iops" {
  description = "IOPS configuradas para o armazenamento"
  type        = number
  default     = 75000
}

variable "admin_username" {
  description = "Nome do usuário administrador PostgreSQL"
  type        = string
  default     = "solidaryadmin"
}

variable "tags" {
  description = "Mapa de tags FinOps obrigatórias"
  type        = map(string)
}
