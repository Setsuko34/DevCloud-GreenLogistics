#!/usr/bin/env bash
set -euo pipefail

# Charge les credentials DEV (non commités) — voir .env.example
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ ! -f "$ROOT_DIR/.env" ]; then
  echo "❌ Fichier .env manquant à la racine du repo. Fais : cp .env.example .env" >&2
  exit 1
fi
set -a; . "$ROOT_DIR/.env"; set +a

echo "==> 1/8 Ingress NGINX"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  --set controller.hostPort.enabled=true \
  --set controller.service.type=NodePort
kubectl -n ingress-nginx rollout status deployment ingress-nginx-controller --timeout=120s

echo "==> 2/8 cert-manager"
helm repo add jetstack https://charts.jetstack.io
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace --set crds.enabled=true
kubectl -n cert-manager rollout status deployment cert-manager --timeout=120s

echo "==> 3/8 Redpanda"
helm repo add redpanda https://charts.redpanda.com
helm upgrade --install redpanda redpanda/redpanda \
  -n messaging --create-namespace \
  --set statefulset.replicas=1 \
  --set-string resources.cpu.cores=1 \
  --set resources.memory.container.max=2Gi \
  --set tls.enabled=false \
  --set external.enabled=false
kubectl -n messaging rollout status statefulset redpanda --timeout=180s

echo "==> 4/8 Vault (dev mode)"
helm repo add hashicorp https://helm.releases.hashicorp.com
helm upgrade --install vault hashicorp/vault \
  -n vault --create-namespace \
  --set "server.dev.enabled=true" \
  --set "server.dev.devRootToken=${VAULT_DEV_ROOT_TOKEN}"
kubectl -n vault wait --for=create pod/vault-0 --timeout=60s
kubectl -n vault wait --for=condition=Ready pod/vault-0 --timeout=180s

echo "==> 5/8 External Secrets Operator"
helm repo add external-secrets https://charts.external-secrets.io
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --set installCRDs=true
kubectl -n external-secrets rollout status deployment external-secrets --timeout=120s

echo "==> 6/8 kube-prometheus-stack + Loki + Promtail"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=30090 \
  --set prometheus.prometheusSpec.retention=2d \
  --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
  --set prometheus.prometheusSpec.resources.limits.memory=1Gi
helm repo add grafana https://grafana.github.io/helm-charts
helm upgrade --install loki grafana/loki -n monitoring \
  --set deploymentMode=SingleBinary \
  --set singleBinary.replicas=1 \
  --set read.replicas=0 --set write.replicas=0 --set backend.replicas=0 \
  --set chunksCache.enabled=false --set resultsCache.enabled=false \
  --set loki.auth_enabled=false \
  --set loki.commonConfig.replication_factor=1 \
  --set loki.storage.type=filesystem \
  --set 'loki.schemaConfig.configs[0].from=2024-01-01' \
  --set 'loki.schemaConfig.configs[0].store=tsdb' \
  --set 'loki.schemaConfig.configs[0].object_store=filesystem' \
  --set 'loki.schemaConfig.configs[0].schema=v13' \
  --set 'loki.schemaConfig.configs[0].index.prefix=index_' \
  --set 'loki.schemaConfig.configs[0].index.period=24h'
helm upgrade --install promtail grafana/promtail -n monitoring \
  --set "config.clients[0].url=http://loki:3100/loki/api/v1/push"

echo "==> 7/8 MailHog"
kubectl create namespace mail --dry-run=client -o yaml | kubectl apply -f -
kubectl -n mail apply -f - <<'MAILHOG'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mailhog
  namespace: mail
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mailhog
  template:
    metadata:
      labels:
        app: mailhog
    spec:
      containers:
        - name: mailhog
          image: mailhog/mailhog:latest
          ports:
            - containerPort: 1025
            - containerPort: 8025
---
apiVersion: v1
kind: Service
metadata:
  name: mailhog
  namespace: mail
spec:
  selector:
    app: mailhog
  ports:
    - name: smtp
      port: 1025
      targetPort: 1025
    - name: http
      port: 8025
      targetPort: 8025
MAILHOG

echo "==> 8/8 Linkerd"
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd check

echo ""
echo "Bootstrap terminé !"
echo "Grafana  : http://localhost:30090  (admin / récupérer avec : kubectl -n monitoring get secret kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
echo "ArgoCD   : installer avec Task 4 (ArgoCD App of Apps)"
echo "MailHog  : kubectl -n mail port-forward svc/mailhog 8025:8025"
