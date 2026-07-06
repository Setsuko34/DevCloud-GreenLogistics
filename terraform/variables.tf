variable "cluster_name" {
  description = "Nom du cluster kind"
  type        = string
  default     = "projet-final"
}

variable "node_image" {
  description = "Image des nodes kind (k8s 1.31+ requis par Linkerd)"
  type        = string
  default     = "kindest/node:v1.31.0"
}

variable "environment" {
  description = "Label env appliqué à toutes les ressources (FinOps §4.8)"
  type        = string
  default     = "dev"
}

variable "team" {
  description = "Label team appliqué à toutes les ressources (FinOps §4.8)"
  type        = string
  default     = "greenlogistics"
}
