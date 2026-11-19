variable "compartment_ocid" {
  description = "OCID do Compartment onde a rede será criada"
  type        = string
}

variable "vcn_cidr" {
  description = "Bloco CIDR principal da VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR da sub-rede pública (Load Balancers)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_oke_subnet_cidr" {
  description = "CIDR da sub-rede privada de aplicação (OKE Worker Nodes)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_db_subnet_cidr" {
  description = "CIDR da sub-rede privada de dados (OCI PostgreSQL)"
  type        = string
  default     = "10.0.3.0/24"
}

variable "tags" {
  description = "Mapa de tags FinOps obrigatórias"
  type        = map(string)
}