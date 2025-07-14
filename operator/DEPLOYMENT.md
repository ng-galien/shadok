# 🚀 Scripts de Déploiement Shadok Operator

Ce répertoire contient les scripts automatisés pour déployer et tester
l'opérateur Shadok dans un cluster Kind.

## 📋 Scripts Disponibles

### 🚀 `deploy-to-kind.sh` - Déploiement Complet

Script principal qui automatise entièrement le déploiement de l'opérateur
Shadok.

**Fonctionnalités :**

- ✅ Configuration et création du cluster Kind
- ✅ Registre Docker local (localhost:5001)
- ✅ Nginx Ingress Controller
- ✅ Construction et déploiement de l'image de l'opérateur
- ✅ Déploiement des CRDs et RBAC
- ✅ Configuration du webhook de mutation des pods
- ✅ Volumes persistants pour sources et cache Java
- ✅ Déploiement des ressources de test
- ✅ Validation complète du déploiement

**Usage :**

```bash
# Déploiement standard
./deploy-to-kind.sh

# Avec logs détaillés
./deploy-to-kind.sh --verbose

# Recréer complètement le cluster
./deploy-to-kind.sh --redeploy-cluster

# Déploiement rapide sans reconstruction
./deploy-to-kind.sh --no-rebuild --skip-tests

# Aide complète
./deploy-to-kind.sh --help
```

**Options principales :**

- `--cluster-name NAME` : Nom du cluster Kind (défaut: shadok-dev)
- `--namespace NS` : Namespace Kubernetes (défaut: shadok)
- `--image-tag TAG` : Tag de l'image (défaut: latest)
- `--no-rebuild` : Ne pas reconstruire l'image
- `--redeploy-cluster` : Supprimer et recréer le cluster
- `--skip-tests` : Ignorer les ressources de test
- `--verbose` : Logs détaillés

### 🧪 `test-deployment.sh` - Validation du Déploiement

Script de test qui valide tous les aspects du déploiement.

**Tests inclus :**

- ✅ Connectivité au cluster
- ✅ Namespace et CRDs
- ✅ Déploiement de l'opérateur
- ✅ Santé des pods et services
- ✅ Configuration RBAC
- ✅ Volumes persistants
- ✅ Configuration du webhook
- ✅ Test fonctionnel du webhook

**Usage :**

```bash
# Exécuter tous les tests
./test-deployment.sh

# Afficher l'état du déploiement
./test-deployment.sh status

# Aide
./test-deployment.sh help
```

## 🔧 Prérequis

Avant d'utiliser ces scripts, assurez-vous d'avoir :

- **Docker** en cours d'exécution
- **Kind** installé (`go install sigs.k8s.io/kind@latest`)
- **kubectl** configuré
- **Gradle** (pour la construction)
- **Ports disponibles** : 80, 443, 5001

## 🚀 Déploiement Rapide

```bash
# 1. Déploiement complet
./deploy-to-kind.sh --verbose

# 2. Validation
./test-deployment.sh

# 3. Vérification de l'état
./test-deployment.sh status
```

## 📊 Après le Déploiement

Une fois le déploiement réussi, vous aurez :

- **Cluster Kind** : `shadok-dev` avec ingress et registre local
- **Namespace** : `shadok` avec l'opérateur déployé
- **Image** : `localhost:5001/shadok/operator:latest`
- **CRDs** : applications.shadok.org, projectsources.shadok.org,
  dependencycaches.shadok.org
- **Webhook** : Pod mutation automatique configuré
- **PVs** : Volumes pour sources et cache Java

### 🔍 Commandes Utiles Post-Déploiement

```bash
# Vérifier les pods
kubectl get pods -n shadok

# Logs de l'opérateur
kubectl logs -n shadok -l app=shadok-operator -f

# Ressources Shadok
kubectl get applications,projectsources,dependencycaches -n shadok

# Configuration du webhook
kubectl get mutatingwebhookconfiguration shadok-pod-mutator

# Test du webhook
kubectl apply -f ../pods/quarkus-hello/k8s/
```

## 🧹 Nettoyage

Pour supprimer complètement le déploiement :

```bash
# Supprimer le cluster Kind
kind delete cluster --name shadok-dev

# Arrêter le registre local
docker stop kind-registry
docker rm kind-registry
```

## 🐛 Dépannage

### Problèmes Courants

1. **Ports occupés** : Vérifiez que les ports 80, 443, 5001 sont libres
2. **Docker non démarré** : `docker info` doit fonctionner
3. **Timeout de construction** : Utilisez `--timeout 600` pour plus de temps
4. **Image non trouvée** : Vérifiez le registre local avec
   `docker ps | grep registry`

### Logs de Débogage

```bash
# Logs détaillés du déploiement
./deploy-to-kind.sh --verbose

# État complet du cluster
kubectl get all -n shadok

# Événements récents
kubectl get events -n shadok --sort-by='.lastTimestamp'

# Décrire les pods problématiques
kubectl describe pods -n shadok
```

## 🎯 Développement

Pour le développement itératif :

```bash
# Reconstruction rapide de l'image seulement
./deploy-to-kind.sh --no-rebuild=false --skip-tests

# Test après modifications
./test-deployment.sh

# Redéploiement avec nouveau code
./gradlew build && docker build -f Dockerfile.gradle -t localhost:5001/shadok/operator:latest . && docker push localhost:5001/shadok/operator:latest
kubectl rollout restart deployment/shadok-operator -n shadok
```
