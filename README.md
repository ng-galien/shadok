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
