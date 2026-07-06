#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# up.sh — Lance toute la stack GreenLogistics en local (cluster kind)
#
# Usage :  ./infra/up.sh
# Idempotent : réutilise le cluster s'il existe déjà.
# Pour tout supprimer :  kind delete cluster --name projet-final
# ─────────────────────────────────────────────────────────────────────────────

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CLUSTER_NAME="projet-final"
NODE_IMAGE="kindest/node:v1.31.0"   # k8s 1.31+ requis par Linkerd

# 0. Prérequis ----------------------------------------------------------------
echo "==> 0/6 Vérification des outils"
missing=0
for tool in docker kind kubectl helm linkerd; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "    ✅ $tool"
  else
    echo "    ❌ $tool introuvable"
    missing=1
  fi
done
if [ "$missing" -eq 1 ]; then
  echo "Installe les outils manquants puis relance." >&2
  exit 1
fi

# 1. Fichier .env -------------------------------------------------------------
echo "==> 1/6 Fichier .env"
if [ ! -f "$ROOT_DIR/.env" ]; then
  cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
  echo "    .env créé depuis .env.example"
else
  echo "    .env déjà présent"
fi

# 2. Cluster kind -------------------------------------------------------------
echo "==> 2/6 Cluster kind ($CLUSTER_NAME)"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "    déjà existant, on réutilise"
else
  kind create cluster --config infra/kind-config.yaml --image "$NODE_IMAGE"
fi
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# 3. Infra (Ingress, Redpanda, Vault, ESO, monitoring, MailHog, Linkerd) ------
echo "==> 3/6 Bootstrap infra (~5-10 min)"
bash infra/bootstrap.sh

# 4. ArgoCD -------------------------------------------------------------------
echo "==> 4/6 ArgoCD"
bash infra/install-argocd.sh

# 5. Topics Kafka + secrets Vault + ClusterSecretStore ------------------------
echo "==> 5/6 Kafka topics + Vault + ClusterSecretStore"
bash infra/setup-kafka-vault.sh

# 6. App of Apps (ArgoCD synchronise la couche applicative depuis main) --------
echo "==> 6/6 Déploiement App of Apps"
kubectl apply -f k8s/argocd/root-app.yaml

# Récapitulatif ---------------------------------------------------------------
cat <<'EOF'

✅ Stack lancée !

  ArgoCD   : https://localhost:30080   (user: admin)
             mot de passe :  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d ; echo
  Grafana  : http://localhost:30090    (user: admin)
             mot de passe :  kubectl -n monitoring get secret kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d ; echo
  MailHog  : kubectl -n mail port-forward svc/mailhog 8025:8025   → http://localhost:8025

  Suivre le déploiement applicatif :
    kubectl get applications -n argocd
    kubectl get pods -n app -w

  Dernière étape manuelle (accès navigateur, nécessite sudo) :
    echo "127.0.0.1 app.greenlogistics.local api.greenlogistics.local" | sudo tee -a /etc/hosts
    → http://app.greenlogistics.local   (frontend)
    → http://api.greenlogistics.local   (API)
EOF
