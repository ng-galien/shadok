# Kubernetes Development Environment

Ce dossier contient les scripts et configurations pour l'environnement de développement Kubernetes avec **kind** (Kubernetes in Docker).

## 🚀 Démarrage rapide

```bash
# Démarrer kind avec la configuration par défaut
./start-kind.sh

# Configuration avancée (cert-manager, dashboard, etc.)
./kind-config.sh

# Vérifier le statut de l'environnement
./status-kind.sh

# Tester l'environnement complet
./test-kind.sh

# Tester les composants avancés
./test-kind-config.sh

# Vérifier les montages des sources pods
./check-pod-mounts.sh

# Arrêter et nettoyer l'environnement
./stop-kind.sh
```

## 📋 Scripts disponibles

| Script | Description | Usage |
|--------|-------------|-------|
| `start-kind.sh` | Démarre l'environnement kind complet avec montages pods | `./start-kind.sh [cluster-name]` |
| `kind-config.sh` | Configure les composants avancés (cert-manager, dashboard, etc.) | `./kind-config.sh [cluster-name]` |
| `stop-kind.sh` | Arrête et nettoie l'environnement | `./stop-kind.sh [cluster-name]` |
| `status-kind.sh` | Vérifie le statut de l'environnement | `./status-kind.sh [cluster-name]` |
| `test-kind.sh` | Teste toutes les fonctionnalités de base | `./test-kind.sh [cluster-name]` |
| `test-kind-config.sh` | Teste les composants avancés | `./test-kind-config.sh [cluster-name]` |
| `check-pod-mounts.sh` | Vérifie les montages des sources pods | `./check-pod-mounts.sh [cluster-name]` |

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

### 📁 Montages des sources pods

- **Montage automatique** des répertoires pods en readonly
- **PersistentVolumes** créés automatiquement pour chaque pod
- **PersistentVolumeClaims** prêts à utiliser
- **Accès depuis les containers** via `/pods/{pod-name}`

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

## 📁 Utilisation des montages de sources pods

### Accès aux sources pods

Les sources de chaque pod sont automatiquement montées dans le cluster kind :

```bash
# Lister les PersistentVolumes des sources
kubectl get pv -l app=shadok

# Lister les PersistentVolumeClaims
kubectl get pvc -l app=shadok

# Exemple d'utilisation dans un deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mon-app
spec:
  template:
    spec:
      containers:
      - name: app
        image: mon-image
        volumeMounts:
        - name: sources
          mountPath: /app/sources
          readOnly: true
      volumes:
      - name: sources
        persistentVolumeClaim:
          claimName: pvc-node-hello-sources
```

### Vérification des montages

```bash
# Vérifier les montages dans les nodes
./check-pod-mounts.sh

# Accès direct aux montages
docker exec kind-shadok-dev-control-plane ls /pods/

# Test depuis un pod
kubectl run test --image=busybox --rm -it -- sh
# ls /pods/
```

## 🛠️ Composants avancés

- **cert-manager** - Gestion automatique des certificats TLS
- **ingress-nginx** - Contrôleur d'ingress avec snippets activés  
- **Kubernetes Dashboard** - Interface web avec auto-login JWT
- **Pod curl-test** - Conteneur de test pour diagnostics réseau
- **Certificats auto-signés** - Pour développement et tests

### Configuration avancée avec Helm

Le script `kind-config.sh` installe automatiquement tous les composants essentiels :

```bash
# Installation automatique lors du démarrage
./start-kind.sh  # Appelle automatiquement kind-config.sh

# Installation manuelle
./kind-config.sh

# Test des composants avancés
./test-kind-config.sh
```

#### Composants installés

```bash
# cert-manager (v1.13.2)
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager --namespace cert-manager

# ingress-nginx avec snippets
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx --set controller.allowSnippetAnnotations=true

# Kubernetes Dashboard avec auto-login
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
# + Ingress avec snippet JWT automatique
```

#### Accès aux services

```bash
# Ajouter à /etc/hosts
echo '127.0.0.1 dashboard.local test.local' | sudo tee -a /etc/hosts

# Accès au dashboard (auto-login activé)
open http://dashboard.local

# Tests avec curl
kubectl exec -it curl-test -- curl http://dashboard.local
```
