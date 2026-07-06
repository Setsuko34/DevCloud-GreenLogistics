# Module réutilisable : namespace K8s avec labels FinOps standard (team/env/app)
# et injection mTLS Linkerd optionnelle.

resource "kubernetes_namespace" "this" {
  metadata {
    name = var.name

    labels = {
      "app"                          = var.app
      "team"                         = var.team
      "env"                          = var.environment
      "app.kubernetes.io/managed-by" = "terraform"
    }

    annotations = var.linkerd_inject ? {
      "linkerd.io/inject" = "enabled"
    } : {}
  }
}
