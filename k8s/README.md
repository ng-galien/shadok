# Kubernetes Development Environment

Ce dossier contient les scripts et configurations pour l'environnement de développement Kubernetes avec **kind** (Kubernetes in Docker).

## 🚀 Démarrage rapide

```bash
# Démarrer kind avec la configuration par défaut
./start-kind.sh

# Vérifier le statut de l'environnement
./status-kind.sh

# Tester l'environnement complet
./test-kind.sh

# Arrêter et nettoyer l'environnement
./stop-kind.sh

# Démarrer avec un nom de cluster personnalisé
./start-kind.sh mon-cluster
```

## 📋 Scripts disponibles

| Script | Description | Usage |
|--------|-------------|-------|
| `start-kind.sh` | Démarre l'environnement kind complet | `./start-kind.sh [cluster-name]` |
| `stop-kind.sh` | Arrête et nettoie l'environnement | `./stop-kind.sh [cluster-name]` |
| `status-kind.sh` | Vérifie le statut de l'environnement | `./status-kind.sh [cluster-name]` |
| `test-kind.sh` | Teste toutes les fonctionnalités | `./test-kind.sh [cluster-name]` |

## 📋 Fonctionnalités

### ✅ Script idempotent

- **Suppression automatique** du cluster existant si présent
- **Recréation complète** à chaque exécution
- **Vérification des prérequis** (kind, docker)

### 🐳 Registry locale intégrée

- **Registry locale** sur `localhost:5001`
- **Mirror GitHub** configuré pour `ghcr.io`
- **Connexion automatique** au cluster kind

### 🌐 Configuration réseau

- **Ingress Controller** NGINX préinstallé
- **Port forwarding** configuré (80, 443)
- **Multi-node** : 1 control-plane + 2 workers

## 🔧 Configuration

### Registry locale

```bash
# Pousser une image vers la registry locale
docker tag mon-image:latest localhost:5001/mon-image:latest
docker push localhost:5001/mon-image:latest

# Utiliser dans un manifest Kubernetes
image: localhost:5001/mon-image:latest
```

### GitHub Container Registry

Le cluster est configuré pour utiliser `ghcr.io` comme mirror :

```yaml
image: ghcr.io/ng-galien/shadok/mon-image:latest
```

## 📦 Prérequis

### Installation des outils

```bash
# macOS avec Homebrew
brew install kind
brew install kubectl
brew install docker

# Démarrer Docker Desktop
open -a Docker
```

### Vérification

```bash
# Vérifier kind
kind version

# Vérifier kubectl
kubectl version --client

# Vérifier docker
docker version
```

## 🛠️ Commandes utiles

### Gestion du cluster

```bash
# Lister les clusters
kind get clusters

# Obtenir le kubeconfig
kind get kubeconfig --name shadok-dev

# Supprimer le cluster
kind delete cluster --name shadok-dev
```

### Gestion de la registry

```bash
# Voir les conteneurs registry
docker ps | grep registry

# Logs de la registry
docker logs shadok-registry

# Supprimer la registry
docker rm -f shadok-registry
```

### Debug

```bash
# État du cluster
kubectl cluster-info
kubectl get nodes -o wide

# État des pods système
kubectl get pods -A

# Logs ingress controller
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
```

## 🏗️ Architecture

```text
┌─────────────────────────────────────┐
│           Host (macOS)              │
│                                     │
│  ┌─────────────────────────────────┐│
│  │      Docker Network (kind)     ││
│  │                                 ││
│  │  ┌─────────────┐ ┌────────────┐ ││
│  │  │ Control     │ │ Worker 1   │ ││
│  │  │ Plane       │ │            │ ││
│  │  └─────────────┘ └────────────┘ ││
│  │                                 ││
│  │  ┌─────────────┐ ┌────────────┐ ││
│  │  │ Worker 2    │ │ Registry   │ ││
│  │  │             │ │ :5000      │ ││
│  │  └─────────────┘ └────────────┘ ││
│  └─────────────────────────────────┘│
│                                     │
│  localhost:5001 → Registry          │
│  localhost:80   → Ingress           │
│  localhost:443  → Ingress (TLS)     │
└─────────────────────────────────────┘
```

## 🔍 Troubleshooting

### Problèmes courants

#### Docker non démarré

```bash
# Erreur: Cannot connect to the Docker daemon
open -a Docker
# Attendre que Docker soit prêt
```

#### Port déjà utilisé

```bash
# Erreur: port 5001 already in use
docker ps | grep 5001
docker rm -f $(docker ps -q --filter "publish=5001")
```

#### Cluster kind bloqué

```bash
# Forcer la suppression
kind delete cluster --name shadok-dev
docker network prune -f
```

#### Registry non accessible

```bash
# Vérifier la connexion
docker network inspect kind
kubectl get configmap -n kube-public local-registry-hosting -o yaml
```

## 🚀 Intégration CI/CD

Le script est conçu pour être utilisé dans des pipelines CI/CD :

```bash
# Dans GitHub Actions
- name: Setup Kind Cluster
  run: |
    ./k8s/start-kind.sh ci-cluster
    kubectl wait --for=condition=ready nodes --all --timeout=300s
```

## 📚 Ressources

- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Local Registry Guide](https://kind.sigs.k8s.io/docs/user/local-registry/)
- [Ingress Controller](https://kind.sigs.k8s.io/docs/user/ingress/)
