#!/usr/bin/env bash
set -euo pipefail

echo "==> 1/4 Creating Redpanda topics"
kubectl -n messaging exec -it redpanda-0 -- rpk topic create gps.positions --partitions 3
kubectl -n messaging exec -it redpanda-0 -- rpk topic create parcels.events --partitions 1

echo "==> Listing Redpanda topics"
kubectl -n messaging exec -it redpanda-0 -- rpk topic list

echo ""
echo "==> 2/4 Provisioning secrets in Vault"
kubectl -n vault exec -it vault-0 -- vault kv put secret/api \
  db_url="postgresql://gl:gl_dev@postgres.app.svc.cluster.local:5432/greenlogistics" \
  db_user="gl" \
  db_password="gl_dev"

echo ""
echo "==> 3/4 Creating external-secrets namespace and vault-token secret"
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
kubectl -n external-secrets create secret generic vault-token \
  --from-literal=token=root --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "==> 4/4 Creating ClusterSecretStore"
kubectl apply -f k8s/infra/cluster-secret-store.yaml

echo ""
echo "==> Verifying ClusterSecretStore"
kubectl get clustersecretstore vault-backend

echo ""
echo "Setup completed successfully!"
