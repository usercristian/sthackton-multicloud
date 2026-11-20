variable "compartment_ocid" {
  description = "OCID do Compartment onde o OKE e o OCIR serão criados"
  type        = string
}

variable "vcn_id" {
  description = "OCID da VCN criada pelo módulo network"
  type        = string
}

variable "public_lb_subnet_id" {
  description = "OCID da sub-rede pública (API Endpoint e Load Balancers)"
  type        = string
}

variable "private_oke_subnet_id" {
  description = "OCID da sub-rede privada dos Worker Nodes"
  type        = string
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes suportada pelo OKE na região"
  type        = string
  default     = "v1.31.1"
}

variable "node_shape" {
  description = "Shape ARM64 dos Worker Nodes"
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "node_ocpus" {
  description = "Quantidade de OCPUs por Worker Node"
  type        = number
  default     = 1
}

variable "node_memory_in_gbs" {
  description = "Memória RAM (GB) por Worker Node"
  type        = number
  default     = 6
}

variable "node_count" {
  description = "Quantidade de Worker Nodes no pool"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Mapa de tags FinOps obrigatórias"
  type        = map(string)
}