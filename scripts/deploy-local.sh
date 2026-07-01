#!/usr/bin/env bash
# ============================================================
#  GreenLogistics — déploiement local complet
#  Simule la stack de production : kind + ArgoCD + Vault +
#  External Secrets + Redpanda + Ingress + Monitoring
#
#  Usage :
#    ./scripts/deploy-local.sh          # déploiement complet
#    ./scripts/deploy-local.sh --clean  # supprime le cluster et repart de zéro
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="greenlogistics"
REGISTRY_NAME="kind-registry"
REGISTRY_PORT="5001"
REG="localhost:${REGISTRY_PORT}"

# ── helpers ──────────────────────────────────────────────────────────────────
blue()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
green() { printf '\033[1;32m    ✓ %s\033[0m\n' "$*"; }
info()  { printf '    %s\n' "$*"; }
err()   { printf '\033[1;31mERREUR: %s\033[0m\n' "$*" >&2; exit 1; }

wait_rollout() {
  local kind="$1" name="$2" ns="${3:-app}" timeout="${4:-120s}"
  info "Attente de ${kind}/${name} dans ${ns}..."
  kubectl -n "$ns" rollout status "${kind}/${name}" --timeout="$timeout"
}

# ── --clean ───────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--clean" ]]; then
  blue "Suppression du cluster '${CLUSTER_NAME}'"
  kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true
  docker rm -f "$REGISTRY_NAME" 2>/dev/null || true
  green "Nettoyage OK — relance le script sans --clean"
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# 0. Prérequis
# ─────────────────────────────────────────────────────────────────────────────
blue "0/9  Prérequis"

for tool in docker kubectl helm; do
  command -v "$tool" &>/dev/null || err "$tool manquant — installe-le d'abord"
done

if ! command -v kind &>/dev/null; then
  info "Installation de kind via brew..."
  brew install kind
fi

if ! command -v argocd &>/dev/null; then
  info "Installation de argocd CLI via brew..."
  brew install argocd
fi

green "Prérequis OK"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Registry Docker locale
# ─────────────────────────────────────────────────────────────────────────────
blue "1/9  Registry locale (localhost:${REGISTRY_PORT})"

if ! docker inspect "$REGISTRY_NAME" &>/dev/null; then
  docker run -d --restart=always \
    -p "127.0.0.1:${REGISTRY_PORT}:5000" \
    --name "$REGISTRY_NAME" \
    registry:2
  green "Registry démarrée"
else
  green "Registry déjà active"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. Cluster kind
# ─────────────────────────────────────────────────────────────────────────────
blue "2/9  Cluster kind '${CLUSTER_NAME}'"

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  green "Cluster déjà en place"
else
  # Config kind : ports exposés + registry locale pour containerd
  cat > /tmp/kind-local.yaml <<KINDEOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
networking:
  podSubnet: "10.244.0.0/16"
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${REGISTRY_PORT}"]
          endpoint = ["http://${REGISTRY_NAME}:5000"]
nodes:
  - role: control-plane
    extraPortMappings:
      - { containerPort: 80,    hostPort: 80,    protocol: TCP }
      - { containerPort: 443,   hostPort: 443,   protocol: TCP }
      - { containerPort: 30080, hostPort: 30080, protocol: TCP }
      - { containerPort: 30090, hostPort: 30090, protocol: TCP }
  - role: worker
KINDEOF
  kind create cluster --config /tmp/kind-local.yaml
  green "Cluster créé"
fi

# Connecte la registry au réseau kind pour que les nœuds puissent la joindre
docker network connect kind "$REGISTRY_NAME" 2>/dev/null || true

kubectl config use-context "kind-${CLUSTER_NAME}"
green "Contexte kubectl : kind-${CLUSTER_NAME}"

# ─────────────────────────────────────────────────────────────────────────────
# 3. Infrastructure Helm
# ─────────────────────────────────────────────────────────────────────────────
blue "3/9  Infra Helm (ingress-nginx, Vault, ESO, Redpanda, Mailhog, Grafana)"

helm repo add ingress-nginx        https://kubernetes.github.io/ingress-nginx          2>/dev/null || true
helm repo add hashicorp            https://helm.releases.hashicorp.com                 2>/dev/null || true
helm repo add external-secrets     https://charts.external-secrets.io                  2>/dev/null || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts  2>/dev/null || true
helm repo update

# ingress-nginx — expose les services via hostPort sur le nœud control-plane
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  --set controller.hostPort.enabled=true \
  --set controller.service.type=NodePort \
  --wait --timeout=120s
green "ingress-nginx OK"

# Vault en mode dev (token root = "root", pas de TLS, redémarre clean à chaque fois)
helm upgrade --install vault hashicorp/vault \
  -n vault --create-namespace \
  --set "server.dev.enabled=true" \
  --set "server.dev.devRootToken=root" \
  --wait --timeout=120s
green "Vault OK  (token root)"

# External Secrets Operator — lit Vault, crée des Secrets k8s
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace \
  --set installCRDs=true \
  --wait --timeout=120s
green "External Secrets Operator OK"

# Redpanda — manifest simple (même config que docker-compose.dev.yml)
# Le chart Helm officiel est trop lourd pour kind
kubectl create namespace messaging --dry-run=client -o yaml | kubectl apply -f -
# Supprime les ressources existantes (ex: reste d'un helm install précédent)
helm -n messaging uninstall redpanda 2>/dev/null || true
kubectl -n messaging delete statefulset redpanda --ignore-not-found
kubectl -n messaging delete service     redpanda --ignore-not-found
kubectl -n messaging apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: redpanda-config
  namespace: messaging
data:
  redpanda.yaml: |
    redpanda:
      data_directory: /var/lib/redpanda/data
      kafka_api:
        - address: 0.0.0.0
          port: 9092
          name: internal
      advertised_kafka_api:
        - address: redpanda.messaging.svc.cluster.local
          port: 9092
          name: internal
      admin:
        - address: 0.0.0.0
          port: 9644
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redpanda
  namespace: messaging
spec:
  serviceName: redpanda
  replicas: 1
  selector:
    matchLabels: { app: redpanda }
  template:
    metadata:
      labels: { app: redpanda }
    spec:
      containers:
        - name: redpanda
          image: redpandadata/redpanda:v24.1.1
          command:
            - redpanda
            - start
            - --smp=1
            - --memory=512M
            - --reserve-memory=0M
            - --overprovisioned
            - --config-file=/etc/redpanda/redpanda.yaml
          ports:
            - { name: kafka, containerPort: 9092 }
            - { name: admin, containerPort: 9644 }
          resources:
            requests: { memory: "512Mi", cpu: "250m" }
            limits:   { memory: "768Mi", cpu: "1000m" }
          readinessProbe:
            httpGet:
              path: /v1/status/ready
              port: 9644
            initialDelaySeconds: 20
            periodSeconds: 10
            failureThreshold: 18
          volumeMounts:
            - name: config
              mountPath: /etc/redpanda
      volumes:
        - name: config
          configMap:
            name: redpanda-config
---
apiVersion: v1
kind: Service
metadata:
  name: redpanda
  namespace: messaging
spec:
  selector: { app: redpanda }
  ports:
    - { name: kafka, port: 9092 }
    - { name: admin, port: 9644 }
EOF
kubectl -n messaging rollout status statefulset/redpanda --timeout=240s
green "Redpanda OK"

# Mailhog (SMTP local)
kubectl create namespace mail --dry-run=client -o yaml | kubectl apply -f -
kubectl -n mail apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mailhog
  namespace: mail
spec:
  replicas: 1
  selector:
    matchLabels: { app: mailhog }
  template:
    metadata:
      labels: { app: mailhog }
    spec:
      containers:
        - name: mailhog
          image: mailhog/mailhog:latest
          ports:
            - { containerPort: 1025 }
            - { containerPort: 8025 }
---
apiVersion: v1
kind: Service
metadata:
  name: mailhog
  namespace: mail
spec:
  selector: { app: mailhog }
  ports:
    - { name: smtp, port: 1025 }
    - { name: http, port: 8025 }
EOF
green "Mailhog OK"

# kube-prometheus-stack (Prometheus + Grafana, NodePort 30090)
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=30090 \
  --set prometheus.prometheusSpec.resources.requests.memory=256Mi \
  --set prometheus.prometheusSpec.resources.limits.memory=512Mi \
  --set alertmanager.enabled=false \
  --wait --timeout=300s
green "Grafana/Prometheus OK  (NodePort 30090)"

# ─────────────────────────────────────────────────────────────────────────────
# 4. Provisioning Vault + topics Redpanda
# ─────────────────────────────────────────────────────────────────────────────
blue "4/9  Vault secrets + topics Redpanda"

kubectl -n vault exec vault-0 -- vault kv put secret/api \
  db_url="postgresql://gl:gl_dev@postgres.app.svc.cluster.local:5432/greenlogistics" \
  db_user="gl" \
  db_password="gl_dev"
green "Secrets Vault créés"

kubectl -n messaging exec redpanda-0 -- rpk topic create gps.positions --partitions 3 2>/dev/null || true
kubectl -n messaging exec redpanda-0 -- rpk topic create parcels.events  --partitions 1 2>/dev/null || true
green "Topics Redpanda créés"

# ─────────────────────────────────────────────────────────────────────────────
# 5. Namespace app + External Secrets → api-secret
# ─────────────────────────────────────────────────────────────────────────────
blue "5/9  Namespace + ClusterSecretStore + ExternalSecret"

kubectl apply -f "${ROOT}/k8s/namespaces/namespaces.yaml"

# Token Vault pour ESO
kubectl -n external-secrets create secret generic vault-token \
  --from-literal=token=root \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "${ROOT}/k8s/infra/cluster-secret-store.yaml"
kubectl apply -f "${ROOT}/k8s/api/external-secret.yaml"

# Attend que ESO crée api-secret (max 90s)
info "Attente de la création du secret 'api-secret' par ESO..."
for i in $(seq 1 18); do
  kubectl -n app get secret api-secret &>/dev/null && break
  sleep 5
done

# Fallback si ESO n'a pas encore synchronisé
if ! kubectl -n app get secret api-secret &>/dev/null; then
  info "ESO pas encore prêt — création manuelle du secret (sera écrasé par ESO ensuite)"
  kubectl -n app create secret generic api-secret \
    --from-literal=DATABASE_URL="postgresql://gl:gl_dev@postgres.app.svc.cluster.local:5432/greenlogistics" \
    --from-literal=DB_USER="gl" \
    --from-literal=DB_PASSWORD="gl_dev" \
    --dry-run=client -o yaml | kubectl apply -f -
fi
green "Secret api-secret prêt"

# ─────────────────────────────────────────────────────────────────────────────
# 6. Postgres + Redis
# ─────────────────────────────────────────────────────────────────────────────
blue "6/9  Postgres + Redis"

kubectl -n app apply -f "${ROOT}/k8s/postgres/"
kubectl -n app apply -f "${ROOT}/k8s/redis/"

wait_rollout statefulset postgres app 120s
wait_rollout deployment   redis    app 60s

# PostgreSQL 15+ : GRANT CREATE sur le schéma public (révoqué par défaut)
kubectl -n app exec statefulset/postgres -- \
  psql -U gl -d greenlogistics -c "GRANT CREATE ON SCHEMA public TO gl;" 2>/dev/null || true

green "Postgres + Redis OK"

# ─────────────────────────────────────────────────────────────────────────────
# 7. Build + push des images (registry locale)
# ─────────────────────────────────────────────────────────────────────────────
blue "7/9  Build images → ${REG}"

for svc in api notification gps frontend; do
  info "Build ${svc}..."
  docker build -t "${REG}/greenlogistics-${svc}:local" \
    "${ROOT}/services/${svc}" \
    --quiet
  docker push "${REG}/greenlogistics-${svc}:local" --quiet
  green "${svc} → ${REG}/greenlogistics-${svc}:local"
done

# ─────────────────────────────────────────────────────────────────────────────
# 8. Déploiement des services applicatifs
# ─────────────────────────────────────────────────────────────────────────────
blue "8/9  Services applicatifs (kubectl apply -k k8s/overlays/local)"

kubectl apply -k "${ROOT}/k8s/overlays/local"

# Migration Prisma via job éphémère
kubectl -n app apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: prisma-migrate
  namespace: app
spec:
  ttlSecondsAfterFinished: 120
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: migrate
          image: localhost:5001/greenlogistics-api:local
          command: ["npx", "prisma", "db", "push", "--skip-generate"]
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: api-secret
                  key: DATABASE_URL
EOF

info "Attente de la migration Prisma..."
kubectl -n app wait --for=condition=complete job/prisma-migrate --timeout=120s

wait_rollout deployment api                app 120s
wait_rollout deployment api-canary         app 120s
wait_rollout deployment frontend           app 120s
wait_rollout deployment frontend-canary    app 120s
wait_rollout deployment notification       app 60s
wait_rollout deployment notification-canary app 60s
wait_rollout deployment gps                app 60s
wait_rollout deployment gps-canary         app 60s

green "Tous les services UP (stable + canary)"

# ─────────────────────────────────────────────────────────────────────────────
# 9. ArgoCD
# ─────────────────────────────────────────────────────────────────────────────
blue "9/9  ArgoCD (GitOps UI)"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl -n argocd rollout status deployment argocd-server --timeout=180s

# Expose sur NodePort 30080
kubectl -n argocd patch svc argocd-server -p \
  '{"spec":{"type":"NodePort","ports":[{"port":443,"targetPort":8080,"nodePort":30080,"protocol":"TCP"}]}}'

ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)

# App of Apps (sync depuis GitHub main — activer après un git push sur main)
info "Application du root App of Apps ArgoCD..."
info "(ArgoCD va tenter de syncer depuis GitHub main — assure-toi d'avoir poussé tes commits)"
kubectl apply -f "${ROOT}/k8s/argocd/root-app.yaml"

green "ArgoCD OK"

# ─────────────────────────────────────────────────────────────────────────────
# /etc/hosts
# ─────────────────────────────────────────────────────────────────────────────
HOSTS_ENTRY="127.0.0.1  app.greenlogistics.local  api.greenlogistics.local"
if ! grep -q "greenlogistics.local" /etc/hosts 2>/dev/null; then
  info "Ajout dans /etc/hosts (sudo requis)..."
  echo "$HOSTS_ENTRY" | sudo tee -a /etc/hosts > /dev/null
  green "/etc/hosts mis à jour"
else
  green "/etc/hosts déjà configuré"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Grafana password
# ─────────────────────────────────────────────────────────────────────────────
GRAFANA_PASS=$(kubectl -n monitoring get secret kps-grafana \
  -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || echo "voir: kubectl -n monitoring get secret kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d")

# ─────────────────────────────────────────────────────────────────────────────
# Résumé
# ─────────────────────────────────────────────────────────────────────────────
cat <<SUMMARY

╔══════════════════════════════════════════════════════════════════╗
║          GreenLogistics — Stack locale déployée                  ║
╠══════════════════════════════════════════════════════════════════╣
║  Frontend    http://app.greenlogistics.local                     ║
║  API         http://api.greenlogistics.local                     ║
║                                                                  ║
║  ArgoCD      https://localhost:30080                             ║
║              admin / ${ARGOCD_PASS}
║                                                                  ║
║  Grafana     http://localhost:30090                              ║
║              admin / ${GRAFANA_PASS}
║                                                                  ║
║  MailHog     kubectl -n mail port-forward svc/mailhog 8025:8025 ║
║              puis → http://localhost:8025                        ║
╠══════════════════════════════════════════════════════════════════╣
║  GitOps : pousse sur main → ArgoCD sync auto                     ║
║  Images locales : ./scripts/deploy-local.sh  (re-build + push)  ║
║  Nettoyage : ./scripts/deploy-local.sh --clean                   ║
╚══════════════════════════════════════════════════════════════════╝

SUMMARY
