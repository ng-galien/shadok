# Python Hello World Pod

Une application Python FastAPI simple qui démontre l'intégration avec Kubernetes
et le système Shadok.

## Fonctionnalités

- **REST API** simple avec endpoints `/hello` et `/hello/json`
- **FastAPI** avec documentation automatique Swagger/OpenAPI
- **Health Checks** configurés (`/health`)
- **Container Image** avec Dockerfile optimisé
- **Live Reload** activé pour le développement
- **Tests** avec pytest

## Endpoints

- `GET /hello` - Retourne un message "Hello World" en texte plain
- `GET /hello/json` - Retourne un message structuré en JSON
- `GET /health` - Health check endpoint
- `GET /docs` - Documentation Swagger automatique
- `GET /redoc` - Documentation ReDoc

## Déploiement

### Développement local

```bash
./start.sh dev
```

L'application sera accessible sur <http://localhost:8000>

### Installation des dépendances

```bash
./start.sh install
```

### Build et conteneur Docker

```bash
./start.sh docker
```

### Test

```bash
./start.sh test
```

## Configuration Kubernetes

L'application est configurée pour :

- **Namespace**: `default`
- **Service Type**: `ClusterIP`
- **Port**: `8000`
- **Labels**:
  - `app.kubernetes.io/name=python-hello`
  - `app.kubernetes.io/part-of=shadok-pods`

## Image Container

- **Name**: `shadok-pods/python-hello`
- **Tag**: `latest`
- **Base**: Python 3.11 Alpine

## Structure du projet

```
src/
  main.py              # Application FastAPI principale
  models.py            # Modèles Pydantic
  config.py            # Configuration
tests/
  test_main.py         # Tests avec pytest
requirements.txt       # Dépendances Python
Dockerfile             # Image container
docker-compose.yml     # Pour développement local
k8s/                   # Manifests Kubernetes
  deployment.yml
  service.yml
```
