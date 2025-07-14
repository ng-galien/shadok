# Shadok

**Shadok** (Simple Hypervisor for Artifact Delivery On Kubernetes) est une
plateforme conçue pour déployer et exécuter des applications en **live reload**
directement depuis leur code source, sans passer par un pipeline CI/CD
classique.

Il permet aux développeurs de travailler de manière interactive dans un cluster
Kubernetes en synchronisant les sources, en gérant les dépendances partagées, et
en assurant le redémarrage conditionnel des pods si nécessaire.

---

## ✨ Objectifs

- Déployer dynamiquement une application à partir de ses **sources (locales ou
  Git)**.
- Exécuter l'application avec un **runtime live reload** (Spring, Quarkus, Node,
  Python, etc.).
- Partager un **cache de dépendances** (`.m2`, `node_modules`, `venv`, etc.).
- Éviter tout déclenchement de pipeline CI/CD.
- Surveiller les changements et **redémarrer les pods intelligemment** si
  nécessaire.

---

## 🧪 Applications de démonstration

Le projet inclut des applications d'exemple pour tester Shadok avec différents
langages :

### 🎯 Commandes rapides

```bash
# Voir le statut de tous les pods
./gradlew podsStatus

# Tester tous les pods
./gradlew testAllPods

# Construire tous les pods
./gradlew buildAllPods

# Configuration complète
./gradlew setupAllPods
```

### ⚡ Pod Quarkus (Java)

Application Quarkus 3.8.1 avec intégration Kubernetes native.

```bash
# Construire le pod Quarkus
./gradlew buildQuarkusPod

# Lancer en mode dev (live reload)
./gradlew runQuarkusDev

# Générer les manifestes Kubernetes
./gradlew generateQuarkusK8s

# URL locale: http://localhost:8080
```

**Endpoints disponibles :**

- `GET /hello` - Message de bienvenue en texte
- `GET /hello/json` - Message de bienvenue en JSON
- `GET /q/health` - Health check Quarkus

### 🐍 Pod Python (FastAPI)

Application FastAPI avec documentation automatique OpenAPI.

```bash
# Configurer l'environnement Python
./gradlew setupPython

# Lancer en mode dev (live reload)
./gradlew runPythonDev

# Construire l'image Docker
./gradlew buildPythonImage

# URL locale: http://localhost:8000
```

**Endpoints disponibles :**

- `GET /hello` - Message de bienvenue en texte
- `GET /hello/json` - Message de bienvenue en JSON
- `GET /health` - Health check
- `GET /docs` - Documentation interactive Swagger

### 📋 Tâches disponibles

```bash
# Python
./gradlew tasks --group python-pods

# Quarkus
./gradlew tasks --group quarkus-pods

# Toutes les tâches pods
./gradlew tasks --group pods
```

### Applications futures

- **Spring Boot** - Application avec Spring Boot Actuator
- **Node.js** - Application Express.js
- **Go** - Application avec Gin
- **.NET** - Application ASP.NET Core

---

## 🐳 Environnement de développement Kubernetes

Shadok inclut un environnement de développement Kubernetes complet basé sur
**kind** (Kubernetes in Docker) avec registry locale intégrée.

### 🚀 Démarrage rapide

```bash
# Démarrer l'environnement kind complet
./k8s/start-kind.sh

# Vérifier le statut
./k8s/status-kind.sh

# Arrêter l'environnement
./k8s/stop-kind.sh
```

### ✨ Fonctionnalités

- **Cluster multi-node** : 1 control-plane + 2 workers
- **Registry locale** sur `localhost:5001`
- **Mirror GitHub** configuré pour `ghcr.io`
- **Ingress Controller** NGINX préinstallé
- **Scripts idempotents** pour un environnement reproductible

### 📦 Utilisation avec les pods

```bash
# Construire et pousser une image locale
docker build -t localhost:5001/shadok/quarkus-hello:latest pods/quarkus-hello/
docker push localhost:5001/shadok/quarkus-hello:latest

# Déployer dans le cluster kind
kubectl apply -f pods/quarkus-hello/k8s/
```

Pour plus de détails, voir [k8s/README.md](k8s/README.md).

---
