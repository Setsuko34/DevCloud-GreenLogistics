# Terraform — GreenLogistics

Module racine + module réutilisable `modules/namespace` pour provisionner le cluster local et sa
base : cluster kind, namespaces (avec labels FinOps `team`/`env`/`app` et injection mTLS Linkerd), et
les Helm releases (Redpanda, Vault, External Secrets Operator, kube-prometheus-stack, ArgoCD).

## Providers

- `tehcyx/kind` — crée le cluster kind (2 nodes, mêmes port mappings que `infra/kind-config.yaml`).
- `hashicorp/kubernetes` — namespaces labellisés.
- `hashicorp/helm` — charts Redpanda/Vault/ESO/kube-prometheus-stack/ArgoCD.

## Statut

`terraform init` + `terraform validate` passent (schémas des 3 providers vérifiés réellement, pas
seulement écrit à la main).

**`terraform apply` n'a volontairement pas été lancé contre le cluster de la démo.** Le cluster
utilisé pour la soutenance a été provisionné plus tôt via `infra/up.sh` (scripts bash idempotents) et
tourne déjà avec toute la stack applicative dessus. Lancer `terraform apply` maintenant risquerait de
recréer/impacter un cluster stable à quelques minutes de la soutenance — le compromis assumé est de
démontrer la compétence IaC (structure, providers, module réutilisable, validation réelle) sans mettre
en danger la démo live.

## Pour l'appliquer réellement (sur une machine propre, sans cluster existant)

```bash
cd terraform
terraform init
terraform apply   # crée un nouveau cluster "projet-final" + namespaces + Helm releases de base
```

Le state reste local (`terraform.tfstate`, non commité — voir `.gitignore`). Après un `apply` réel,
ArgoCD (déployé par ce module) doit encore être synchronisé sur `k8s/argocd/root-app.yaml` pour que les
4 applications (`api`, `gps`, `notification`, `frontend`) se déploient — cf. étapes 6-7 de
`infra/up.sh`, non dupliquées ici pour éviter la divergence entre les deux chemins de provisioning
(bash / Terraform) qui coexistent pendant la transition.
