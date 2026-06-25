# GreenLogistics

Plateforme de suivi de colis en temps réel — Kubernetes (kind), Go GPS simulator, React/Leaflet frontend.

---

## Architecture

```
Browser → Frontend (Nginx) → API REST (Personne 1)
                                  ↕
GPS Simulator (Go) → Redpanda → Notification service
         ↓
       Redis (position courante)
```

| Service | Techno | Namespace K8s |
|---|---|---|
| API REST | Node.js/Go | `app` |
| GPS Simulator | Go | `app` |
| Frontend | React + Nginx | `app` |
| Notification | — | `app` |
| Redpanda | Kafka-compatible | `messaging` |
| Redis | Redis 7 | `app` |
| Vault | Dev mode | `vault` |
| ArgoCD | GitOps | `argocd` |
| Grafana/Prometheus/Loki | Monitoring | `monitoring` |
| MailHog | SMTP de test | `mail` |

---

## Prérequis

- Docker Desktop (≥ 4.x)
- [kind](https://kind.sigs.k8s.io/) ≥ 0.23
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/) ≥ 3.14
- [Linkerd CLI](https://linkerd.io/2/getting-started/)
- Go ≥ 1.22
- Node.js ≥ 20

---

## 1. Cluster kind

```bash
kind create cluster --config infra/kind-config.yaml --image kindest/node:v1.30.0
kubectl cluster-info --context kind-projet-final
kubectl get nodes   # 2 nodes Ready
```

---

## 2. Bootstrap plateforme

Installe Ingress NGINX, cert-manager, Redpanda, Vault, External Secrets, Prometheus/Grafana/Loki, MailHog, Linkerd.

```bash
chmod +x infra/bootstrap.sh
./infra/bootstrap.sh
```

Accès après bootstrap :
- **Grafana** : http://localhost:30090 — `admin` / `kubectl -n monitoring get secret kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d`
- **MailHog** : `kubectl -n mail port-forward svc/mailhog 8025:8025` → http://localhost:8025

---

## 3. Topics Redpanda + secrets Vault

```bash
chmod +x infra/setup-kafka-vault.sh
./infra/setup-kafka-vault.sh
```

Vérifie :
```bash
kubectl -n messaging exec -it redpanda-0 -- rpk topic list
# doit lister gps.positions et parcels.events

kubectl get clustersecretstore vault-backend
# STATUS: Valid
```

---

## 4. ArgoCD — App of Apps

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deployment argocd-server --timeout=180s

# Exposer l'UI
kubectl -n argocd patch svc argocd-server \
  -p '{"spec":{"type":"NodePort","ports":[{"port":443,"nodePort":30080,"protocol":"TCP"}]}}'

# Password initial
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Déployer l'App of Apps
kubectl apply -f k8s/argocd/root-app.yaml
```

ArgoCD UI : https://localhost:30080 — `admin` / mot de passe ci-dessus.

ArgoCD sync les 4 apps automatiquement depuis `main` : `api`, `gps`, `notification`, `frontend`.

---

## 5. /etc/hosts

```bash
echo "127.0.0.1 app.greenlogistics.local api.greenlogistics.local" | sudo tee -a /etc/hosts
```

---

## 6. Vérifier les pods

```bash
kubectl get pods -n app
# api, gps, frontend, notification → Running
```

---

## Test en local (sans cluster K8s)

### GPS simulator seul

Requiert Redis et Redpanda en Docker :

```bash
docker run -d --name redis -p 6379:6379 redis:7-alpine

docker run -d --name redpanda -p 9092:9092 \
  redpandadata/redpanda:latest \
  redpanda start --overprovisioned --smp 1 --memory 512M \
  --reserve-memory 0M --node-id 0 --check=false

cd services/gps
REDPANDA_BROKERS=localhost:9092 REDIS_URL=localhost:6379 go run main.go
```

Vérifier Redis :
```bash
docker exec redis redis-cli get "driver:driver-1:pos"
```

### Frontend seul

```bash
cd services/frontend
npm install
npm run dev   # http://localhost:5173
```

Les appels API échouent sans le backend (Personne 1), mais la UI charge.

Avec l'API disponible sur le port 3000 :
```bash
VITE_API_URL=http://localhost:3000 npm run dev
```

### Docker builds

```bash
# GPS
cd services/gps
docker build -t greenlogistics-gps:local .

# Frontend
cd services/frontend
docker build -t greenlogistics-frontend:local .
docker run --rm -p 8080:80 greenlogistics-frontend:local
# http://localhost:8080
```

---

## Démo E2E complète

1. Vérifier ArgoCD : `argocd app list` → toutes les apps `Synced / Healthy`
2. Vérifier les pods : `kubectl get pods -n app`
3. Ouvrir le frontend : http://app.greenlogistics.local
4. Créer un colis via `POST http://api.greenlogistics.local/parcels`
5. Suivre le colis sur la TrackingPage — la carte Leaflet se met à jour toutes les 5s
6. Attendre la notification email (livreur < 1 km) : http://localhost:8025 (après port-forward MailHog)

Test self-heal ArgoCD :
```bash
kubectl scale deploy/api -n app --replicas=0
# ArgoCD remet à 1 automatiquement en < 30s
```

---

## Structure du dépôt

```
infra/              # kind config + bootstrap script
services/
├── gps/            # Simulateur GPS Go
└── frontend/       # SPA React + Vite + Leaflet
k8s/
├── argocd/         # App of Apps
├── gps/            # Deployment GPS
└── frontend/       # Deployment + Service + Ingress frontend
docs/               # Plans et specs
```
