# Pods

Ce répertoire contient les applications de démonstration pour différents langages et frameworks, utilisées pour tester la plateforme Shadok.

## Applications disponibles

### Quarkus Hello (`quarkus-hello/`)

Une application Quarkus simple qui démontre :

- REST API avec JAX-RS
- Intégration Kubernetes native
- Container Image avec Jib
- Live Reload pour le développement
- Health Checks

**Endpoints** :
- `GET /hello` - Message Hello World en texte
- `GET /hello/json` - Message Hello World en JSON
- `GET /q/health` - Health check

**Démarrage rapide** :

```bash
cd quarkus-hello
./start.sh dev
```

### Python Hello (`python-hello/`)

Une application Python FastAPI simple qui démontre :

- REST API avec FastAPI
- Documentation Swagger/OpenAPI automatique
- Container Image optimisé Alpine
- Live Reload pour le développement
- Health Checks et tests pytest

**Endpoints** :
- `GET /hello` - Message Hello World en texte
- `GET /hello/json` - Message Hello World en JSON
- `GET /health` - Health check
- `GET /docs` - Documentation Swagger

**Démarrage rapide** :

```bash
cd python-hello
./start.sh dev
```

## Applications futures

- **Spring Boot** - Application Spring Boot avec actuator
- **Node.js** - Application Express.js
- **Go** - Application avec Gin
- **.NET** - Application ASP.NET Core

## Structure type d'une application pod

Chaque application pod doit contenir :

1. **Code source** dans une structure standard pour le langage
2. **Configuration Kubernetes** (natif ou via manifests)
3. **Dockerfile** pour la containerisation
4. **README.md** avec instructions de démarrage
5. **Script de démarrage** (`start.sh` ou équivalent)
6. **Tests** unitaires et d'intégration

## Intégration avec Shadok

Toutes les applications sont conçues pour être compatibles avec :
- **Live Reload** - Rechargement automatique du code
- **Cache de dépendances** - Partage `.m2`, `node_modules`, etc.
- **Déploiement dynamique** - Sans pipeline CI/CD
- **Surveillance** - Redémarrage intelligent des pods
