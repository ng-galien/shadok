# 🧪 Test Live Reload avec Git Patches - Guide d'Utilisation

Ce document explique comment utiliser le nouveau système de test de live reload basé sur des patches Git pour valider la recompilation automatique du webservice Quarkus.

## 🎯 Objectif

Tester de manière réaliste et automatisée que :
- Les modifications de code sont détectées en temps réel
- La recompilation Quarkus se déclenche automatiquement 
- Les changements sont immédiatement visibles via l'API HTTP
- Le retour à l'état initial fonctionne correctement

## 🚀 Utilisation

### Option 1: Test intégré au script principal

```bash
# Test complet incluant le live reload du webservice
./test-operator.sh

# Test rapide (sans live reload)
./test-operator.sh --quick
```

### Option 2: Test dédié du webservice

```bash
# Aller dans le répertoire du webservice
cd pods/quarkus-hello

# Test automatique avec patches Git
./test-live-reload-patch.sh --verbose

# Test avec configuration personnalisée
./test-live-reload-patch.sh --timeout 60 --namespace shadok --verbose
```

### Option 3: Test manuel étape par étape

```bash
# 1. Déployer le pod de test live reload
kubectl apply -f pods/quarkus-hello/test-live-reload-pod.yaml

# 2. Attendre que le pod soit prêt
kubectl wait --for=condition=ready pod/quarkus-hello-live-reload -n shadok --timeout=60s

# 3. Exécuter le test
cd pods/quarkus-hello
./test-live-reload-patch.sh --pod-name quarkus-hello-live-reload

# 4. Nettoyer
kubectl delete -f test-live-reload-pod.yaml
```

## 🔍 Ce que teste le script

### Workflow automatisé :

1. **Test initial** : `GET /hello/json` → Réponse de base
2. **Application patch Git** : Modification de `HelloWorldResource.helloJson()`
3. **Attente recompilation** : Détection automatique du changement (max 30s)
4. **Validation modification** : `GET /hello/json` → Nouvelle réponse
5. **Revert patch** : `git checkout -- .`
6. **Validation retour** : `GET /hello/json` → Réponse de base

### Exemple de patch appliqué :

```java
// AVANT (état initial)
return new HelloResponse("Hello World from Quarkus Pod!", "quarkus-hello", "1.0.0");

// APRÈS (patch appliqué)
return new HelloResponse("🧪 LIVE RELOAD TEST ACTIVE! 🚀", "quarkus-hello-patched", "2.0.0-LIVE");
```

## 📊 Résultats attendus

### ✅ Test réussi :
```
🏆 RÉSULTAT: SUCCÈS COMPLET

✅ Fonctionnalités validées:
  • Live reload automatique actif
  • Recompilation en temps réel fonctionnelle  
  • Détection des changements de code
  • Workflow Git patch/revert opérationnel
  • Endpoints HTTP réactifs aux modifications

📈 Métriques:
  • Timeout configuré: 30s
  • Pod testé: quarkus-hello-live-reload
  • Namespace: shadok
```

### ❌ Test échoué :
```
❌ RÉSULTAT: ÉCHEC

🔧 Points à vérifier:
  • Le pod dispose-t-il du live reload activé ?
  • Les volumes source/cache sont-ils montés ?
  • Quarkus dev mode est-il actif dans le conteneur ?
  • La commande './gradlew quarkusDev' est-elle utilisée ?
```

## 🔧 Configuration requise

### Prérequis système :
- `kubectl` configuré et accessible
- `curl` installé
- `git` disponible 
- Cluster Kubernetes avec namespace `shadok`

### Prérequis déploiement :
- Opérateur Shadok déployé et fonctionnel
- Webhook de mutation configuré
- CRDs `Application`, `ProjectSource`, `DependencyCache` disponibles

### Structure attendue :
```
pods/quarkus-hello/
├── src/main/java/com/shadok/pods/quarkus/
│   └── HelloWorldResource.java          # Fichier modifié par le patch
├── test-live-reload-patch.sh            # Script de test principal
├── test-live-reload-pod.yaml            # Manifeste du pod de test
└── .git/                               # Repository git requis
```

## 🎯 Avantages de cette approche

### vs Test manuel :
- ✅ **Automatisation complète** : Aucune intervention manuelle
- ✅ **Reproductibilité** : Résultats identiques à chaque exécution
- ✅ **Rapidité** : Test complet en < 60 secondes
- ✅ **Validation exhaustive** : Test aller-retour complet

### vs Modification directe de fichiers :
- ✅ **Workflow réaliste** : Simule un vrai développement Git
- ✅ **Nettoyage automatique** : Retour automatique à l'état initial
- ✅ **Traçabilité** : Patches Git versionnés et reproductibles
- ✅ **Sécurité** : Aucun risque de corruption du code source

## 🚀 Intégration CI/CD

Ce test peut être intégré dans des pipelines CI/CD pour valider automatiquement le live reload :

```yaml
# Exemple GitHub Actions
- name: Test Live Reload
  run: |
    ./test-operator.sh --quick  # Tests de base
    cd pods/quarkus-hello
    ./test-live-reload-patch.sh --timeout 45  # Test live reload
```

## 🔍 Dépannage

### Pod ne démarre pas :
```bash
kubectl describe pod quarkus-hello-live-reload -n shadok
kubectl logs quarkus-hello-live-reload -n shadok
```

### Recompilation non détectée :
```bash
# Vérifier les logs du pod en temps réel
kubectl logs -f quarkus-hello-live-reload -n shadok

# Vérifier les volumes montés
kubectl exec quarkus-hello-live-reload -n shadok -- ls -la /workspace
```

### Endpoint non accessible :
```bash
# Tester la connectivité directement
kubectl exec quarkus-hello-live-reload -n shadok -- curl localhost:8080/hello
```

---

**🎉 Ce système de test valide de manière exhaustive et automatisée que le live reload fonctionne parfaitement avec l'opérateur Shadok !**
