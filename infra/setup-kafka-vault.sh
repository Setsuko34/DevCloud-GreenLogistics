#!/usr/bin/env bash
set -euo pipefail

# Charge les credentials DEV (non commités) — voir .env.example
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ ! -f "$ROOT_DIR/.env" ]; then
  echo "❌ Fichier .env manquant à la racine du repo. Fais : cp .env.example .env" >&2
  exit 1
fi
set -a; . "$ROOT_DIR/.env"; set +a

DB_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres.app.svc.cluster.local:5432/${POSTGRES_DB}"

echo "==> 1/4 Creating Redpanda topics"
create_topic() {  # idempotent : ne recrée pas un topic existant
  local name=$1 parts=$2
  if kubectl -n messaging exec redpanda-0 -- rpk topic list 2>/dev/null | grep -qw "$name"; then
    echo "topic $name déjà présent"
  else
    kubectl -n messaging exec -it redpanda-0 -- rpk topic create "$name" --partitions "$parts"
  fi
}
create_topic gps.positions 3
create_topic parcels.events 1

echo "==> Listing Redpanda topics"
kubectl -n messaging exec -it redpanda-0 -- rpk topic list

echo ""
echo "==> 2/4 Provisioning secrets in Vault"
kubectl -n vault exec -it vault-0 -- vault kv put secret/api \
  db_url="${DB_URL}" \
  db_user="${POSTGRES_USER}" \
  db_password="${POSTGRES_PASSWORD}"

echo ""
echo "==> 3/4 Creating external-secrets namespace and vault-token secret"
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
kubectl -n external-secrets create secret generic vault-token \
  --from-literal=token="${VAULT_DEV_ROOT_TOKEN}" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "==> 4/4 Creating ClusterSecretStore"
kubectl apply -f k8s/infra/cluster-secret-store.yaml

echo ""
echo "==> Verifying ClusterSecretStore"
kubectl get clustersecretstore vault-backend

echo ""
echo "Setup completed successfully!"
