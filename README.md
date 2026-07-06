# GreenLogistics

Plateforme de tracking temps réel de livraison dernière mile — startup de livraison écologique.
Suivi de colis en direct, notification d'arrivée automatique, dashboard opérationnel — sur un cluster
Kubernetes 100% local (kind), en GitOps (ArgoCD), messagerie événementielle (Redpanda/Kafka),
observabilité complète (Prometheus/Grafana/Loki) et mTLS (Linkerd).

Projet réalisé dans le cadre du module *Développer pour le Cloud* (YNOV Campus, M2, 2025-2026) —
voir [docs/Sujet.pdf](docs/Sujet.pdf) et [docs/ADR.md](docs/ADR.md) pour les décisions d'architecture.

---

## Pitch

Un livreur envoie sa position GPS toutes les 5 secondes. Le client suit son colis en direct sur une carte,
reçoit un mail automatique quand le livreur est à moins d'1 km, et le statut du colis (`CREATED` →
`IN_TRANSIT` → `DELIVERED`) se met à jour tout seul à partir de la position réelle — sans intervention
manuelle. Un dashboard interne liste tous les colis en cours avec leur position mise à jour en direct
(WebSocket, alimenté par Kafka).

## Architecture

```
Browser ──HTTP──► Frontend (Nginx + React/Leaflet)
                        │  proxy /parcels, /ws
                        ▼
                   API REST (Fastify/Node)  ──consomme──  Kafka: gps.positions
                    │        │      │        └─produit──► Kafka: parcels.events
                    │        │      └─push WebSocket──► Frontend (positions live)
                    │        └─lit/écrit──► Redis (position courante par livreur)
                    └─lit/écrit──► PostgreSQL (colis, événements)

GPS Simulator (Go) ──produit──► Kafka: gps.positions, parcels.events
                     └─écrit───► Redis (position courante)

Kafka: parcels.events ──consomme──► Notification service ──SMTP──► MailHog
```

| Service | Techno | Rôle | Namespace K8s |
|---|---|---|---|
| `frontend` | React + Vite + Leaflet + Nginx | SPA suivi colis + dashboard | `app` |
| `api` | Node.js/Fastify + Prisma | REST colis, positions, WebSocket live | `app` |
| `gps` | Go | Simulateur de livreurs (positions GPS) | `app` |
| `notification` | Node.js + nodemailer | Consomme `parcels.events` → email | `app` |
| `postgres` | PostgreSQL 16 | Persistance colis/événements | `app` |
| `redis` | Redis 7 | Position GPS courante (cache TTL) | `app` |
| Redpanda | Kafka-compatible | Bus événementiel (`gps.positions`, `parcels.events`) | `messaging` |
| Vault + External Secrets Operator | Dev-mode | Secrets hors Git | `vault` / `external-secrets` |
| ArgoCD | GitOps App of Apps | Déploiement continu depuis `main` | `argocd` |
| Prometheus/Grafana/Loki/Alertmanager | kube-prometheus-stack | Observabilité, logs, alerting | `monitoring` |
| Linkerd | Service mesh | mTLS automatique (namespace `app`) | `linkerd` |
| MailHog | SMTP de test | Réception des emails simulés | `mail` |

## Fonctionnalités

- **API colis** : création, recherche par code de suivi, historique d'événements, liste (dashboard).
- **Ingestion GPS événementielle** : le simulateur Go publie une position par livreur toutes les 5s sur
  Kafka (`gps.positions`) et Redis (cache "position courante").
- **Notification automatique** : dès qu'un livreur est à moins d'1 km de la destination, l'API publie un
  événement `near_5min` sur Kafka (`parcels.events`) ; le service notification le consomme et envoie un
  email (avec le code de suivi et un lien direct vers la page de suivi).
- **Statut auto-géré** : `CREATED` → `IN_TRANSIT` dès la première position reçue, → `DELIVERED` sous
  100m de la destination — sans appel manuel.
- **Dashboard temps réel** : liste tous les colis, statut et position mise à jour en direct via WebSocket
  (`/ws/positions`), alimenté par un consumer Kafka intégré à l'API (pas de microservice dédié).
- **Suivi public** : page de suivi avec carte Leaflet, historique des statuts, lien direct `?code=...`
  (celui envoyé par email).

## Prérequis

- Docker Desktop (≥ 4.x) — pour construire les images et faire tourner kind.
- `kind`, `kubectl`, `helm`, `linkerd` CLI — installés automatiquement, sans sudo, par
  `./infra/install-tools.sh` (voir §Installation).
- Go ≥ 1.26 / Node.js ≥ 20 (uniquement pour développer/tester en local hors cluster).

## Installation (reproductible en < 30 min)

```bash
# 1. Outils CLI (kubectl, kind, helm, linkerd) dans ~/.local/bin — sans sudo
./infra/install-tools.sh

# 2. Résolution DNS locale
echo "127.0.0.1 app.greenlogistics.local api.greenlogistics.local" | sudo tee -a /etc/hosts

# 3. Cluster + toute la stack (kind, ingress, Redpanda, Vault, ESO, monitoring, Linkerd, ArgoCD, App of Apps)
./infra/up.sh
```

`up.sh` est idempotent (réutilise le cluster s'il existe déjà) et orchestre, dans l'ordre :
1. Vérification des outils
2. `.env` (copié depuis `.env.example` si absent)
3. Cluster `kind` (2 nodes, config `infra/kind-config.yaml`)
4. `infra/bootstrap.sh` — Ingress NGINX, cert-manager, Redpanda, Vault (dev-mode), External Secrets
   Operator, kube-prometheus-stack, Loki/Promtail, MailHog, Linkerd
5. `infra/install-argocd.sh` — ArgoCD, exposé en NodePort
6. `infra/setup-kafka-vault.sh` — topics Kafka + secrets Vault + ClusterSecretStore
7. `kubectl apply -f k8s/argocd/root-app.yaml` — App of Apps : ArgoCD synchronise ensuite les 4
   applications (`api`, `gps`, `notification`, `frontend`) depuis la branche `main`

### Accès une fois la stack levée

| Service | URL | Identifiants |
|---|---|---|
| Frontend | http://app.greenlogistics.local | — |
| API | http://api.greenlogistics.local | — |
| ArgoCD | https://localhost:30080 | `admin` / `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d` |
| Grafana | http://localhost:30090 | `admin` / `kubectl -n monitoring get secret kps-grafana -o jsonpath='{.data.admin-password}' \| base64 -d` |
| MailHog | http://localhost:8025 | `kubectl -n mail port-forward svc/mailhog 8025:8025` |

## Démo

```bash
# Crée 3 colis à intervalles sur 5 minutes, simule leur déplacement (départ ~15-20km de la
# destination), laisse l'API gérer statut + notification automatiquement
./infra/demo-parcels.sh
```

Pendant que ça tourne :
- Dashboard : http://app.greenlogistics.local/dashboard — statut et position se mettent à jour en direct.
- MailHog : http://localhost:8025 — email "arrivée dans 5 min" avec lien de suivi.

Vérifier le self-heal ArgoCD en live :
```bash
kubectl scale deploy/api -n app --replicas=0
# ArgoCD remet à 2 automatiquement en < 30s (syncPolicy.automated.selfHeal)
kubectl get applications -n argocd
```

## Canary (Argo Rollouts)

Le service `api` est un `Rollout` (Argo Rollouts) plutôt qu'un `Deployment` classique — canary 20% avec
analyse automatique basée sur le SLO d'erreur déjà en place (`api:error_ratio:rate5m`) :

```bash
kubectl argo rollouts get rollout api -n app --watch
```

Déclencher un nouveau rollout (ex. après un bump d'image par la CI) : le canary passe à 20% du
trafic, pause 60s, puis l'`AnalysisTemplate` interroge Prometheus — si le taux d'erreur dépasse 5%,
**rollback automatique** vers 100% stable. Revert manuel à tout moment :

```bash
kubectl argo rollouts abort api -n app    # bascule immédiatement 100% stable
kubectl argo rollouts undo api -n app     # revient à la révision précédente
```

## CI/CD (GitOps pull-based)

`push` sur `main` déclenche `.github/workflows/ci.yaml` : lint + tests unitaires + build multi-stage +
scan Trivy (échec si CVE `CRITICAL`) pour les 4 services, en parallèle (matrice). La CI **ne touche
jamais le cluster** : elle pousse les images sur `ghcr.io` (tag `:<sha>` et `:latest`), puis committe
elle-même le nouveau tag dans `k8s/<service>/deployment.yaml` directement sur `main`. ArgoCD (dans le
cluster, `automated: {prune, selfHeal}`) détecte ce commit et redéploie — aucune authentification
CI → cluster nécessaire.

## Développement local (sans cluster K8s)

```bash
cp .env.example .env
docker compose -f docker-compose.dev.yml up --build
```
Lance Postgres, Redis, Redpanda, MailHog et les 4 services en local avec hot-reload.

## Structure du dépôt

```
infra/              # install-tools.sh, kind-config, bootstrap/up/demo scripts
services/
├── api/            # REST Fastify + Prisma + WebSocket + consumer/producer Kafka
├── gps/            # Simulateur GPS (Go)
├── notification/   # Consumer Kafka → email (nodemailer)
└── frontend/       # SPA React + Vite + Leaflet
k8s/
├── argocd/         # App of Apps
├── api/ gps/ frontend/ notification/ postgres/ redis/  # manifestes par service
└── infra/          # ClusterSecretStore (Vault → External Secrets)
docs/
├── Sujet.pdf, Guide-Sujet.pdf   # sujet du projet
├── ADR.md                       # décisions d'architecture
└── architecture.md              # diagramme Mermaid détaillé
```

## Documentation complémentaire

- [docs/ADR.md](docs/ADR.md) — décisions d'architecture (Contexte / Décision / Conséquences)
- [docs/architecture.md](docs/architecture.md) — diagramme Mermaid détaillé
