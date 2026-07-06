# Miroir Terraform des installations Helm faites par infra/bootstrap.sh et
# infra/install-argocd.sh (mêmes charts/valeurs) — cf. terraform/README.md pour le
# statut (validé, non appliqué contre le cluster de démo).

resource "helm_release" "redpanda" {
  name             = "redpanda"
  repository       = "https://charts.redpanda.com"
  chart            = "redpanda"
  namespace        = module.namespace["messaging"].name
  create_namespace = false

  set {
    name  = "statefulset.replicas"
    value = "1"
  }
  set {
    name  = "tls.enabled"
    value = "false"
  }
  set {
    name  = "external.enabled"
    value = "false"
  }
}

resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  namespace        = module.namespace["vault"].name
  create_namespace = false

  set {
    name  = "server.dev.enabled"
    value = "true"
  }
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = module.namespace["external-secrets"].name
  create_namespace = false

  set {
    name  = "installCRDs"
    value = "true"
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kps"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = module.namespace["monitoring"].name
  create_namespace = false

  set {
    name  = "grafana.service.type"
    value = "NodePort"
  }
  set {
    name  = "grafana.service.nodePort"
    value = "30090"
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = module.namespace["argocd"].name
  create_namespace = false
}
