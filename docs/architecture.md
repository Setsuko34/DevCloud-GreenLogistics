# Architecture — GreenLogistics

```mermaid
flowchart LR
    subgraph Client
        Browser[Navigateur]
    end

    subgraph ns_app["namespace: app (mTLS Linkerd)"]
        Frontend["frontend<br/>React + Nginx"]
        API["api<br/>Fastify + Prisma<br/>(Rollout canary)"]
        GPS["gps<br/>simulateur Go"]
        Notif["notification<br/>nodemailer"]
        Postgres[("postgres")]
        Redis[("redis<br/>position courante")]
    end

    subgraph ns_messaging["namespace: messaging"]
        Redpanda{{"Redpanda<br/>gps.positions / parcels.events"}}
    end

    subgraph ns_mail["namespace: mail"]
        MailHog["MailHog<br/>SMTP de test"]
    end

    subgraph ns_monitoring["namespace: monitoring"]
        Prometheus[("Prometheus")]
        Grafana["Grafana"]
        Loki[("Loki")]
        Alertmanager["Alertmanager"]
    end

    subgraph ns_argocd["namespace: argocd"]
        ArgoCD["ArgoCD<br/>App of Apps"]
    end

    Browser -->|HTTP| Frontend
    Frontend -->|"proxy /parcels"| API
    Frontend <-->|"proxy /ws (WebSocket)"| API

    API --> Postgres
    API <--> Redis
    API -->|consomme| Redpanda
    API -->|produit near_5min| Redpanda

    GPS -->|produit positions| Redpanda
    GPS --> Redis

    Redpanda -->|consomme near_5min| Notif
    Notif -->|SMTP| MailHog

    ArgoCD -.->|sync depuis main, self-heal| Frontend
    ArgoCD -.-> API
    ArgoCD -.-> GPS
    ArgoCD -.-> Notif

    Prometheus -.->|scrape /metrics| API
    Promtail["promtail"] -.->|logs| Loki
    Grafana --> Prometheus
    Grafana --> Loki
    Alertmanager --> Prometheus
```

## Flux "notification d'arrivée"

```mermaid
sequenceDiagram
    participant G as GPS Simulator / demo script
    participant A as API
    participant K as Redpanda (parcels.events)
    participant N as Notification
    participant M as MailHog

    G->>A: POST /dev/seed-position (lat, lng, parcel_id)
    A->>A: distance haversine → destination
    alt distance <= 1km
        A->>K: produit event near_5min (tracking_code, recipient_email)
    end
    alt distance <= 100m
        A->>A: statut = DELIVERED
    else première position
        A->>A: statut = IN_TRANSIT
    end
    K->>N: consomme near_5min
    N->>M: envoie l'email (lien de suivi ?code=...)
```

## Canary — Argo Rollouts (service `api`)

```mermaid
flowchart LR
    subgraph ns_argorollouts["namespace: argo-rollouts"]
        Controller["Argo Rollouts<br/>controller"]
    end

    Controller -.->|orchestre| Rollout["Rollout api (app)<br/>5 replicas"]
    Rollout -->|"setWeight: 20"| Canary["20% canary"]
    Canary -->|"pause 60s"| Analysis["AnalysisTemplate<br/>api-error-rate"]
    Analysis -->|query| Prom[("Prometheus<br/>api:error_ratio:rate5m")]
    Analysis -->|"< 5% erreurs"| Full["setWeight: 100<br/>(100% stable)"]
    Analysis -->|"≥ 5% erreurs"| Rollback["abandon auto<br/>→ 100% stable"]
```

Détails et alternatives évaluées : [ADR-7](ADR.md#adr-7--argo-rollouts-canary-basé-sur-les-replicas-plutôt-que-linkerd-smiistio).

## CI/CD — GitOps pull-based

```mermaid
flowchart LR
    Dev["git push origin main"] --> CI["GitHub Actions<br/>lint + test + build + trivy scan"]
    CI -->|push image :sha / :latest| GHCR[("ghcr.io")]
    CI -->|commit bump image tag| Repo["k8s/&lt;service&gt;/deployment.yaml"]
    ArgoCD["ArgoCD<br/>(dans le cluster)"] -.->|poll + sync + self-heal| Repo
    ArgoCD --> Cluster["Pods redéployés"]
    GHCR -.->|image pull| Cluster
```
