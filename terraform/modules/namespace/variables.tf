variable "name" {
  description = "Nom du namespace Kubernetes"
  type        = string
}

variable "app" {
  description = "Label app.kubernetes.io/part-of / app"
  type        = string
}

variable "team" {
  type = string
}

variable "environment" {
  type = string
}

variable "linkerd_inject" {
  description = "Active l'injection mTLS Linkerd sur ce namespace"
  type        = bool
  default     = false
}
