locals {
  namespaces = {
    app              = { app = "greenlogistics", linkerd_inject = true }
    messaging        = { app = "redpanda", linkerd_inject = false }
    vault            = { app = "vault", linkerd_inject = false }
    external-secrets = { app = "external-secrets", linkerd_inject = false }
    monitoring       = { app = "kube-prometheus-stack", linkerd_inject = false }
    mail             = { app = "mailhog", linkerd_inject = false }
    argocd           = { app = "argocd", linkerd_inject = false }
  }
}

module "namespace" {
  for_each = local.namespaces
  source   = "./modules/namespace"

  name           = each.key
  app            = each.value.app
  team           = var.team
  environment    = var.environment
  linkerd_inject = each.value.linkerd_inject
}
