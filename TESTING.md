# 🧪 Guide de Test - Opérateur Kubernetes Shadok

## 📋 Vue d'Ensemble

Ce document détaille le processus de test complet pour l'opérateur Kubernetes
Shadok, incluant la validation du refactoring fonctionnel, du live reload et des
CRDs.

## 🎯 Objectifs des Tests

1. **Validation du Refactoring Fonctionnel** : Vérifier que le code Java 21
   moderne fonctionne
2. **Test du Live Reload** : Confirmer que les modifications sont appliquées en
   temps réel
3. **Validation des CRDs** : S'assurer que tous les reconcilers fonctionnent
   correctement
4. **Test d'Intégration** : Vérifier l'orchestration complète des ressources

## 🏗️ Prérequis

### Infrastructure

- ✅ **Kind cluster** démarré et fonctionnel
- ✅ **Namespace `shadok`** créé
- ✅ **CRDs** déployées automatiquement par l'opérateur

### Outils

- ✅ **kubectl** configuré pour le cluster Kind
- ✅ **Java 21** pour Quarkus dev mode
- ✅ **Gradle** pour la compilation

## 🚀 Processus de Test Complet

### Phase 1 : Préparation et Démarrage

```bash
# 1. Démarrer Kind cluster
./kind/start-kind.sh

# 2. Créer le namespace
kubectl create namespace shadok

# 3. Démarrer l'opérateur en mode dev avec live reload
cd shadok
./gradlew quarkusDev
```

### Phase 2 : Test des CRDs Individuels

#### 🗄️ **Test DependencyCache**

```bash
# Appliquer le CRD DependencyCache
kubectl apply -f test-dependencycache.yaml

# Vérifier la création automatique de la PVC
kubectl get pvc -n shadok
kubectl get dependencycache -n shadok test-cache -o yaml

# Logs attendus :
# "INFO [org.sha.ope.con.DependencyCacheReconciler] Reconciling DependencyCache: shadok/test-cache"
# "DEBUG [org.sha.ope.con.DependencyCacheReconciler] All dependent resources are ready"
```

#### 📦 **Test ProjectSource**

```bash
# Appliquer le CRD ProjectSource
kubectl apply -f test-projectsource.yaml

# Vérifier la création automatique de la PVC
kubectl get pvc -n shadok
kubectl get projectsource -n shadok test-project -o yaml

# Logs attendus :
# "INFO [org.sha.ope.con.ProjectSourceReconciler] Reconciling ProjectSource: shadok/test-project"
# "DEBUG [org.sha.ope.con.ProjectSourceReconciler] All dependent resources are ready"
```

#### 🚀 **Test Application (Le Plus Complexe)**

```bash
# Appliquer le CRD Application
kubectl apply -f test-application.yaml

# Vérifier le statut avec la nouvelle logique DependencyState
kubectl get application -n shadok test-app -o yaml

# Status attendu :
# state: PENDING
# message: "Both ProjectSource 'test-project' and DependencyCache 'test-cache' are not ready"
```

### Phase 3 : Test du Live Reload

#### 🔄 **Modification de Code en Temps Réel**

1. **Modifier un message de log** dans `ApplicationReconciler.java`
2. **Observer la recompilation automatique** (environ 1.4s)
3. **Déclencher une réconciliation** :
   ```bash
   kubectl patch application test-app -n shadok --type='merge' -p='{"metadata":{"labels":{"test":"live-reload"}}}'
   ```
4. **Vérifier le nouveau message** dans les logs

#### ✅ **Résultat Attendu**

```
INFO [io.qua.dep.dev.RuntimeUpdatesProcessor] Live reload total time: 1.399s
INFO [org.sha.ope.con.ApplicationReconciler] 🚀 Reconciling Application avec le nouveau code fonctionnel: shadok/test-app
```

## 📊 Validation des Améliorations

### 🏗️ **Architecture Fonctionnelle**

| Composant               | Fonctionnalité Testée                           | Status |
| ----------------------- | ----------------------------------------------- | ------ |
| `ResourceCheckResult`   | Sealed interface + pattern matching             | ✅     |
| `DependencyState`       | Enum avec logique métier intelligente           | ✅     |
| `ApplicationReconciler` | Style fonctionnel avec Optional chains          | ✅     |
| Live Reload             | Modification code → recompilation → application | ✅     |

### 🔍 **Points de Validation**

1. **Type Safety** : Aucune erreur de compilation avec les nouveaux types
2. **Performance** : Live reload en moins de 2 secondes
3. **Robustesse** : Gestion d'erreur avec retry automatique (conflit 409)
4. **Observabilité** : Logs détaillés avec niveaux DEBUG/INFO appropriés

## 🎯 Critères de Succès

### ✅ **Tests Réussis Si :**

- [ ] **Tous les CRDs** se déploient sans erreur
- [ ] **PVCs créées automatiquement** par les reconcilers
- [ ] **Status mis à jour correctement** avec la nouvelle logique
- [ ] **Live reload fonctionne** en moins de 2 secondes
- [ ] **Logs affichent les nouveaux messages** après modification
- [ ] **Aucune exception** dans les logs pendant les tests

### ❌ **Indicateurs d'Échec :**

- Erreurs de compilation Java 21
- CRDs non reconnus par l'opérateur
- PVCs non créées après réconciliation
- Live reload non fonctionnel
- Exceptions non gérées dans les logs

## 🧹 Nettoyage Après Tests

```bash
# Supprimer les ressources de test
kubectl delete application test-app -n shadok
kubectl delete projectsource test-project -n shadok
kubectl delete dependencycache test-cache -n shadok

# Optionnel : Arrêter le cluster Kind
./kind/stop-kind.sh
```

## 📈 Métriques de Performance

### ⏱️ **Temps de Référence**

| Opération           | Temps Attendu | Tolérance |
| ------------------- | ------------- | --------- |
| Démarrage opérateur | 3-5 secondes  | ±2s       |
| Réconciliation CRD  | <1 seconde    | ±0.5s     |
| Live reload         | 1.4 secondes  | ±0.5s     |
| Création PVC        | 2-3 secondes  | ±1s       |

## 🔧 Dépannage

### 🐛 **Problèmes Fréquents**

1. **Kind cluster non accessible**

   ```bash
   kubectl cluster-info
   ./kind/status-kind.sh
   ```

2. **CRDs non déployées**

   ```bash
   kubectl get crd | grep shadok
   ```

3. **Live reload non fonctionnel**

   - Vérifier que Quarkus dev mode est actif
   - S'assurer qu'aucun processus ne bloque les fichiers

4. **Reconcilers non déclenchés**
   ```bash
   kubectl logs -f deployment/shadok-operator -n shadok-system
   ```

## 🏆 Conclusion

Ce processus de test valide l'excellence technique du refactoring :

- ✨ **Java 21 moderne** avec sealed interfaces
- ⚡ **Live reload** opérationnel pour le développement
- 🎯 **Code fonctionnel** robuste et maintenable
- 🛡️ **Type safety** garantie par le compilateur

**Tests réussis = Opérateur prêt pour la production !** 🚀
