# Session — Review infra & k8s + ordre de lancement local

> Date : 2026-07-01 | Branche : `fix/docker-compose-all`

---

## Contexte

Vérification que les dossiers `infra/` et `k8s/` sont complets pour lancer le projet localement tel que demandé par le sujet.

---

## État des fichiers au moment de la session

### `infra/` — complet ✅

| Fichier | Rôle |
|---------|------|
| `kind-config.yaml` | Cluster kind 2 nodes (control-plane + worker), ports 80/443/30080/30090 |
| `bootstrap.sh` | Installe via Helm : Ingress NGINX, cert-manager, Redpanda, Vault (dev), External Secrets Operator, Prometheus/Grafana/Loki, MailHog, Linkerd |
| `install-argocd.sh` | Installe ArgoCD et expose l'UI sur NodePort 30080 |
| `setup-kafka-vault.sh` | Crée les topics Redpanda (`gps.positions`, `parcels.events`), peuple Vault (`secret/api`), crée le ClusterSecretStore |

### `k8s/` — lacunes identifiées ❌

Les dossiers `k8s/redis/` et `k8s/postgres/` existaient avec leurs manifests mais **n'étaient référencés dans aucune ArgoCD app**. Le dossier `k8s/namespaces/` (namespace `app` avec annotation Linkerd) était dans le même cas.

Résultat : ArgoCD ne les aurait jamais déployés.

---

## Ce qui a été ajouté

Trois fichiers créés dans `k8s/argocd/apps/` :

### `namespaces-app.yaml` — wave `"0"`
```yaml
path: k8s/namespaces
```
Déploie le namespace `app` avec l'annotation `linkerd.io/inject: enabled` avant tout le reste.

### `redis-app.yaml` — wave `"2"`
```yaml
path: k8s/redis
```
Déploie Redis avant les services applicatifs.

### `postgres-app.yaml` — wave `"4"`
```yaml
path: k8s/postgres
```
Même wave que `api` — le StatefulSet Postgres lit le secret `api-secret` créé par l'ExternalSecret (dans `k8s/api/`). En wave 4, les deux se déploient en parallèle et Kubernetes retry Postgres jusqu'à ce que le secret existe.

> Pourquoi pas wave 2 pour postgres ? L'ExternalSecret qui crée `api-secret` est dans `k8s/api/` (wave 4). Si postgres est en wave 2, le secret n'existe pas encore → CrashLoop. En wave 4, retry automatique.

---

## Ordre des sync-waves ArgoCD après les ajouts

| Wave | App(s) | Path(s) |
|------|--------|---------|
| 0 | `namespaces` | `k8s/namespaces` |
| 2 | `redis` | `k8s/redis` |
| 4 | `api`, `gps`, `frontend`, `notification`, `postgres` | `k8s/<service>` |

---

## Ordre de lancement local (2 scripts)

Sur une machine vierge (Linux/WSL2), **Docker doit déjà être installé**. Ensuite :

```bash
# 1. Installer les CLI (kubectl, kind, helm, linkerd) dans ~/.local/bin — SANS sudo, SANS npm
./infra/install-tools.sh

# 2. Tout lancer : cluster kind 1.31 + infra + ArgoCD + topics/Vault + App of Apps
./infra/up.sh

# 3. Accès navigateur (une fois, nécessite sudo)
echo "127.0.0.1 app.greenlogistics.local api.greenlogistics.local" | sudo tee -a /etc/hosts
```

`up.sh` est **idempotent** (réutilise le cluster s'il existe) et enchaîne : vérif outils → `.env`
(copié depuis `.env.example`) → cluster kind → `bootstrap.sh` → `install-argocd.sh` →
`setup-kafka-vault.sh` → root-app. Il affiche le récap (URLs + mots de passe) à la fin.

Repartir de zéro : `kind delete cluster --name projet-final` puis `./infra/up.sh`.

### Ce que fait `up.sh` en détail
| Étape | Script | Rôle |
|-------|--------|------|
| Cluster | `kind create … --image kindest/node:v1.31.0` | 2 nodes (k8s **1.31** requis par Linkerd) |
| Infra | `bootstrap.sh` | Ingress, cert-manager, Redpanda, Vault, ESO, Prometheus/Grafana/Loki, MailHog, Gateway API + Linkerd |
| ArgoCD | `install-argocd.sh` | ArgoCD (`kubectl apply --server-side`) + UI NodePort 30080 |
| Kafka/Vault | `setup-kafka-vault.sh` | topics `gps.positions`/`parcels.events`, secret `secret/api`, ClusterSecretStore |
| App | `kubectl apply root-app.yaml` | App of Apps → waves : namespaces → redis → services |

### Reproduire sur un autre PC (démo)
Le déploiement est **GitOps** : la machine est jetable, l'état vit dans `main` (manifests, via ArgoCD)
et sur **GHCR** (images, via la CI). Pour que la démo fonctionne à l'identique, il faut donc :
`main` à jour **et** la CI passée verte (images publiées). Aucune build locale.

### Notes
- `bootstrap.sh` prend ~5-10 min (Redpanda et Linkerd sont lents à démarrer)
- Postgres peut CrashLoop/retry le temps qu'`api-secret` soit créé par l'ExternalSecret — normal
- Surveiller : `kubectl get pods -n app -w` ou UI ArgoCD `https://localhost:30080` (admin / `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`)
- Grafana : `http://localhost:30090` (admin / `kubectl -n monitoring get secret kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d`)
- MailHog : `kubectl -n mail port-forward svc/mailhog 8025:8025` → `http://localhost:8025`
- Credentials dev dans `.env` (gitignoré, copié auto depuis `.env.example` par `up.sh`)

---

## Architecture rappel

```
Browser → Frontend (Nginx) → API REST
                                  ↕
GPS Simulator (Go) → Redpanda → Notification service
         ↓
       Redis (position courante)
         ↕
      PostgreSQL (persistence)
```

| Service | Image | Namespace |
|---------|-------|-----------|
| API REST | `ghcr.io/setsuko34/greenlogistics-api:latest` | `app` |
| GPS Simulator | `ghcr.io/setsuko34/greenlogistics-gps:latest` | `app` |
| Frontend | `ghcr.io/setsuko34/greenlogistics-frontend:latest` | `app` |
| Notification | `ghcr.io/setsuko34/greenlogistics-notification:latest` | `app` |
| Redis | `redis:7-alpine` | `app` |
| PostgreSQL | `postgres:16-alpine` | `app` |
| Redpanda | Helm chart | `messaging` |
| Vault | Helm chart (dev mode, token=`root`) | `vault` |
| ArgoCD | manifests upstream | `argocd` |
| Grafana/Prometheus/Loki | Helm chart | `monitoring` |
| MailHog | manifest inline | `mail` |

---

## Points d'attention pour la reprise

- Toutes les ArgoCD apps pointent sur `repoURL: https://github.com/Setsuko34/DevCloud-GreenLogistics` branche `main` — les changements doivent être mergés dans `main` pour qu'ArgoCD les récupère
- Le secret Vault est en mode dev (`token=root`), ne pas utiliser en prod
- Broker Redpanda (chart Helm) : listener Kafka sur le port **9093** (pas 9092) — les env `REDPANDA_BROKERS` de api/gps/notification pointent dessus
- Dockerfile api : `openssl` requis dans le stage runner (moteur Prisma), sinon crash `Unable to require libquery_engine`
