#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# install-tools.sh — Installe les CLI nécessaires SANS sudo, dans ~/.local/bin
#   kubectl, kind, helm, linkerd
#
# Cible : Linux / WSL2 (x86_64).
# ⚠️  Docker doit être installé à part (Docker Desktop ou Docker Engine).
#     Ces outils NE sont PAS des paquets npm — n'utilise jamais `npm install`.
# ─────────────────────────────────────────────────────────────────────────────

BIN_DIR="$HOME/.local/bin"
KIND_VERSION="v0.24.0"
HELM_VERSION="v3.21.2"

mkdir -p "$BIN_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> kubectl (dernière stable)"
KVER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
curl -fsSLo "$TMP/kubectl" "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
install -m 0755 "$TMP/kubectl" "$BIN_DIR/kubectl"

echo "==> kind ${KIND_VERSION}"
curl -fsSLo "$TMP/kind" "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
install -m 0755 "$TMP/kind" "$BIN_DIR/kind"

echo "==> helm ${HELM_VERSION}"
curl -fsSL -o "$TMP/helm.tgz" "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
tar -xzf "$TMP/helm.tgz" -C "$TMP" linux-amd64/helm
install -m 0755 "$TMP/linux-amd64/helm" "$BIN_DIR/helm"

echo "==> linkerd (dernière release)"
LTAG="$(curl -fsSL https://api.github.com/repos/linkerd/linkerd2/releases/latest | grep -m1 '"tag_name"' | cut -d'"' -f4)"
curl -fsSLo "$TMP/linkerd" "https://github.com/linkerd/linkerd2/releases/download/${LTAG}/linkerd2-cli-${LTAG}-linux-amd64"
install -m 0755 "$TMP/linkerd" "$BIN_DIR/linkerd"

# S'assurer que ~/.local/bin est dans le PATH
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *)
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo "⚠️  ~/.local/bin ajouté à ~/.bashrc — ouvre un nouveau terminal (ou 'source ~/.bashrc')."
    ;;
esac

echo
echo "✅ Installés dans $BIN_DIR :"
"$BIN_DIR/kubectl" version --client 2>/dev/null | head -1
"$BIN_DIR/kind" version
"$BIN_DIR/helm" version --short
"$BIN_DIR/linkerd" version --client --short 2>/dev/null || true
echo
echo "Docker doit être installé à part. Ensuite :  ./infra/up.sh"
