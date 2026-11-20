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
  default     = "v1.36.4"
}

variable "node_shape" {
  description = "Shape ARM64 dos Worker Nodes (ex: VM.Standard.A2.Flex ou VM.Standard.A1.Flex)"
  type        = string
  default     = "VM.Standard.A2.Flex"
}

variable "fault_domains" {
  description = "Lista opcional de Fault Domains para restringir o posicionamento dos nós (vazio usa todos os FDs)"
  type        = list(string)
  default     = []
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