# Quarkus Hello World Pod

Une application Quarkus simple qui démontre l'intégration avec Kubernetes et le système Shadok.

## Fonctionnalités

- **REST API** simple avec endpoints `/hello` et `/hello/json`
- **Configuration Kubernetes** intégrée avec l'extension `quarkus-kubernetes`
- **Container Image** automatique avec Jib
- **Live Reload** activé pour le développement
- **Health Checks** configurés

## Endpoints

- `GET /hello` - Retourne un message "Hello World" en texte plain
- `GET /hello/json` - Retourne un message structuré en JSON
- `GET /health` - Health check endpoint

## Déploiement

### Développement local

```bash
./gradlew quarkusDev
```

L'application sera accessible sur http://localhost:8080

### Build et génération des manifests Kubernetes

```bash
./gradlew build
```

Les manifests Kubernetes seront générés dans `build/kubernetes/`

### Test

```bash
./gradlew test
```

## Configuration Kubernetes

L'application est configurée pour :
- **Namespace**: `default`
- **Service Type**: `ClusterIP`
- **Port**: `8080`
- **Labels**: 
  - `app.kubernetes.io/name=quarkus-hello`
  - `app.kubernetes.io/part-of=shadok-pods`

## Image Container

- **Group**: `shadok-pods`
- **Name**: `quarkus-hello`
- **Tag**: `latest`

L'image est construite automatiquement avec Jib lors du build.
