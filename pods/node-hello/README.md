# Node.js Hello World Pod

Un pod de démonstration Node.js avec Express pour la plateforme Shadok.

## 🚀 Caractéristiques

- **Framework**: Express.js pour les API REST
- **Live Reload**: Développement avec nodemon
- **Sécurité**: Helmet.js et CORS
- **Tests**: Jest et Supertest
- **Santé**: Endpoints de health check
- **Docker**: Image optimisée Alpine Linux
- **Kubernetes**: Support complet avec health checks

## 📋 Prérequis

- Node.js 18+
- npm 9+

## 🔧 Installation

```bash
# Installation des dépendances
npm install

# Ou utiliser le script
./start.sh install
```

## 🎯 Utilisation

### Mode développement (avec live reload)

```bash
# Démarrage avec nodemon
npm run dev

# Ou utiliser le script
./start.sh dev
```

### Mode production

```bash
# Démarrage normal
npm start

# Ou utiliser le script
./start.sh prod
```

### Tests

```bash
# Tests unitaires
npm test

# Tests avec watch mode
npm run test:watch

# Tests des endpoints (serveur doit être démarré)
./test-endpoints.sh
```

## 🌐 Endpoints disponibles

| Endpoint      | Méthode | Description                   |
| ------------- | ------- | ----------------------------- |
| `/`           | GET     | Informations du service       |
| `/hello`      | GET     | Salutation simple (texte)     |
| `/hello/json` | GET     | Réponse JSON détaillée        |
| `/health`     | GET     | Vérification de santé         |
| `/ready`      | GET     | Vérification de disponibilité |

## 🔍 Exemples de réponses

### GET /

```json
{
  "message": "Hello from Node.js!",
  "service": "node-hello",
  "version": "1.0.0",
  "timestamp": "2025-07-13T10:30:00.000Z",
  "environment": "development"
}
```

### GET /hello

```
Hello World from Node.js Express server! 🚀
```

### GET /hello/json

```json
{
  "greeting": "Hello World!",
  "technology": "Node.js + Express",
  "platform": "Shadok",
  "features": [
    "Express.js web framework",
    "Live reload with nodemon",
    "Security with Helmet",
    "CORS support",
    "JSON responses",
    "Health checks"
  ],
  "uptime": 45.123,
  "memory": {...},
  "nodeVersion": "v18.19.0"
}
```

## 🐳 Docker

### Construction

```bash
docker build -t node-hello .
```

### Exécution

```bash
docker run -p 3000:3000 node-hello
```

## ⚙️ Variables d'environnement

- `PORT`: Port d'écoute (défaut: 3000)
- `HOST`: Adresse d'écoute (défaut: 0.0.0.0)
- `NODE_ENV`: Environnement (development/production)

## 🧪 Scripts disponibles

- `npm start` - Démarrage en mode production
- `npm run dev` - Démarrage avec live reload
- `npm test` - Exécution des tests
- `npm run lint` - Vérification du code
- `npm run lint:fix` - Correction automatique du code

## 📦 Dépendances principales

- **express**: Framework web rapide et minimaliste
- **helmet**: Middleware de sécurité
- **cors**: Support Cross-Origin Resource Sharing
- **nodemon**: Live reload pour le développement
- **jest**: Framework de tests
- **supertest**: Tests d'intégration HTTP
