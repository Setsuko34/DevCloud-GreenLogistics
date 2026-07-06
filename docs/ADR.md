# Architecture Decision Records — GreenLogistics

## ADR-7 : Argo Rollouts (canary basé sur les replicas) plutôt que Linkerd SMI/Istio

**Contexte** : le sujet exige un déploiement progressif (canary ou blue/green) sur au moins un
service, avec une vraie possibilité de revert en cas de problème. Linkerd est déjà installé pour le
mTLS, mais l'extension `linkerd-smi` (nécessaire pour un `TrafficSplit` précis) n'est pas déployée, et
Istio est écarté pour son empreinte mémoire (cf. ADR-4).

**Décision** : Argo Rollouts (recommandé par le sujet), en canary "basique" sans mesh de trafic dédié —
le `Service` `api` existant route déjà vers les pods stable et canary proportionnellement à leur nombre
(mécanisme natif de Kubernetes). Le service `api` passe de 2 à 5 replicas pour permettre un pas de 20%
exact (1 pod sur 5), et une `AnalysisTemplate` interroge directement la recording rule
`api:error_ratio:rate5m` (déjà en place pour le SLO 1) pendant la pause du canary : si le taux d'erreur
dépasse 5%, Argo Rollouts abandonne automatiquement et repasse à 100% stable.

**Conséquences** : pas de nouvelle brique d'infra lourde (pas de SMI/Istio à opérer), et réutilisation
directe de l'observabilité déjà construite (SLO → décision de rollback automatique). Revert manuel
toujours disponible et immédiat : `kubectl argo rollouts abort api -n app` (bascule 100% stable) ou
`kubectl argo rollouts undo api -n app` (retour à la révision précédente). Contrepartie assumée : sans
mesh, la précision du split dépend du nombre total de replicas (5 replicas pour un pas de 20%, pas
générique à n'importe quel pourcentage).

## ADR-1 : Redpanda comme bus événementiel (plutôt que RabbitMQ/NATS)

**Contexte** : le suivi de colis exige un flux continu de positions GPS (1 point/5s/livreur) et des
événements métier (`near_5min`) consommés par un service indépendant (notification), sans coupler
producteurs et consommateurs.

**Décision** : Redpanda (compatible protocole Kafka), avec deux topics — `gps.positions` (haute
fréquence, position brute) et `parcels.events` (événements métier ponctuels, ex. `near_5min`).

**Conséquences** : API Kafka standard (`kafkajs`, `segmentio/kafka-go`) réutilisable partout sans
dépendance à un broker spécifique ; Redpanda est plus léger que Kafka+Zookeeper pour un cluster local
(1 seul binaire). Contrepartie : pas de Dead Letter Queue mise en place (hors scope du temps imparti).

## ADR-2 : Redis comme cache de position courante, Postgres comme source de vérité métier

**Contexte** : la position GPS change toutes les 5s et n'a de valeur que récente (TTL naturel) ; le
statut/historique d'un colis doit être durable et cohérent.

**Décision** : Redis stocke uniquement `driver:<id>:pos` avec TTL (300s), clé courante par livreur.
PostgreSQL (via Prisma) est la seule source de vérité pour `Parcel`/`ParcelEvent`.

**Conséquences** : aucune position historique n'est conservée (seulement la dernière) — acceptable pour
un tracking temps réel, pas pour du reporting de trajet. Simplifie fortement le modèle par rapport à un
stockage de séries temporelles dédié (hors scope).

## ADR-3 : Consumer/producer Kafka intégrés à l'API plutôt qu'un microservice dédié

**Contexte** : le dashboard doit afficher la position de tous les colis en direct. Deux options :
un microservice "position-gateway" séparé, ou intégrer le consumer/producer directement à l'API REST déjà
existante.

**Décision** : l'API Fastify embarque un plugin Kafka (`positions-feed.ts`) qui consomme
`gps.positions` et relaie en WebSocket (`/ws/positions`) aux clients connectés, et produit sur
`parcels.events` (transition de statut) depuis `/dev/seed-position`.

**Conséquences** : un microservice de moins à déployer/opérer/monitorer pour un gain limité (le volume
reste faible pour une démo). Contrepartie assumée : l'API a maintenant une responsabilité de plus
(temps réel) en plus du CRUD classique — acceptable ici, à revoir si le trafic grossit réellement.

## ADR-4 : Linkerd plutôt qu'Istio pour le service mesh

**Contexte** : exigence de mTLS automatique intra-cluster sur au moins un namespace, sur une machine de
développement avec RAM limitée.

**Décision** : Linkerd (annotation `linkerd.io/inject: enabled` sur le namespace `app`), plutôt qu'Istio.

**Conséquences** : Linkerd est nettement plus léger (proxy Rust minimal) et suffit largement au besoin
(mTLS auto, pas de policy de routage avancée requise). Istio aurait apporté VirtualService/DestinationRule
utiles pour un canary fin, mais au prix d'une empreinte mémoire bien plus lourde sur un cluster local
kind à 2 nodes.

## ADR-5 : GitOps pull-based (ArgoCD) plutôt que push depuis la CI

**Contexte** : la CI (GitHub Actions) doit déployer sur un cluster kind qui tourne sur une machine
locale, sans exposition réseau stable ni identité fédérée (pas d'équivalent Workload Identity local).

**Décision** : la CI ne détient aucune credential vers le cluster. Elle construit/scanne/pousse les
images sur GHCR, puis committe elle-même le nouveau tag d'image dans `k8s/<service>/deployment.yaml`
sur `main`. ArgoCD (`syncPolicy.automated: {prune, selfHeal}`), qui tourne dans le cluster, détecte le
commit et synchronise.

**Conséquences** : élimine tout besoin d'auth CI → cluster (pas de kubeconfig à sécuriser, pas de
tunnel/webhook). Contrepartie : latence de quelques minutes (poll ArgoCD) entre le merge et le déploiement
effectif, sauf sync manuel forcé.

## ADR-6 : Vault dev-mode + External Secrets Operator plutôt que Secrets K8s en clair

**Contexte** : les secrets (URL de base de données notamment) ne doivent pas être committés en clair
dans les manifestes Git, tout en restant simples à faire fonctionner sur un cluster local jetable.

**Décision** : HashiCorp Vault en mode dev (token root fixe, pas de unseal) + External Secrets Operator,
qui synchronise les secrets Vault vers de vrais K8s `Secret` consommés par les déploiements
(`k8s/api/external-secret.yaml`, `k8s/infra/cluster-secret-store.yaml`).

**Conséquences** : aucun secret en clair dans Git. Le mode dev de Vault n'est pas production-ready
(token root statique, pas de scellement) — assumé et documenté, cohérent avec le contexte pédagogique
« cluster local jetable, zéro budget ».
