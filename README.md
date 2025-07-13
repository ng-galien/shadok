# Shadok

**Shadok** (Simple Hypervisor for Artifact Delivery On Kubernetes) est une plateforme conçue pour déployer et exécuter des applications en **live reload** directement depuis leur code source, sans passer par un pipeline CI/CD classique. 

Il permet aux développeurs de travailler de manière interactive dans un cluster Kubernetes en synchronisant les sources, en gérant les dépendances partagées, et en assurant le redémarrage conditionnel des pods si nécessaire.

---

## ✨ Objectifs

- Déployer dynamiquement une application à partir de ses **sources (locales ou Git)**.
- Exécuter l'application avec un **runtime live reload** (Spring, Quarkus, Node, Python, etc.).
- Partager un **cache de dépendances** (`.m2`, `node_modules`, `venv`, etc.).
- Éviter tout déclenchement de pipeline CI/CD.
- Surveiller les changements et **redémarrer les pods intelligemment** si nécessaire.

---

## 🧪 Applications de démonstration

Le répertoire `pods/` contient des applications de démonstration pour différents langages et frameworks :

### Quarkus Hello (`pods/quarkus-hello/`)

Application Quarkus simple avec :
- **REST API** avec endpoints `/hello` et `/hello/json`
- **Intégration Kubernetes native** avec l'extension quarkus-kubernetes
- **Container Image** automatique avec Jib
- **Live Reload** activé pour le développement
- **Health Checks** configurés (`/q/health/*`)

**Démarrage rapide** :
```bash
cd pods/quarkus-hello
./start.sh dev
```

### Python Hello (`pods/python-hello/`)

Application Python FastAPI simple avec :

- **REST API** avec FastAPI et endpoints `/hello` et `/hello/json`
- **Documentation automatique** Swagger/OpenAPI accessible sur `/docs`
- **Container Image** optimisé avec Alpine Linux
- **Live Reload** activé pour le développement
- **Health Checks** configurés (`/health`)
- **Tests** avec pytest

**Démarrage rapide** :

```bash
cd pods/python-hello
./start.sh dev
```

### Applications futures

- **Spring Boot** - Application avec Spring Boot Actuator
- **Node.js** - Application Express.js
- **Go** - Application avec Gin
- **.NET** - Application ASP.NET Core

---
