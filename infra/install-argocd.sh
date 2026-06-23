#!/bin/bash
# ArgoCD installation script for GreenLogistics

set -e

echo "Step 1: Creating argocd namespace..."
kubectl create namespace argocd

echo "Step 2: Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Step 3: Waiting for ArgoCD server to be ready..."
kubectl -n argocd rollout status deployment argocd-server --timeout=180s

echo "Step 4: Exposing ArgoCD UI on NodePort 30080..."
kubectl -n argocd patch svc argocd-server -p '{"spec":{"type":"NodePort","ports":[{"port":443,"nodePort":30080,"protocol":"TCP"}]}}'

echo "Step 5: Retrieving initial admin password..."
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d ; echo

echo ""
echo "ArgoCD installation complete!"
echo "Access the UI at: https://localhost:30080"
echo "Username: admin"
