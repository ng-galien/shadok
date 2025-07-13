# Shadok

Shadok est un opérateur Kubernetes qui facilite le développement en direct (live
development) en gérant auto```yaml apiVersion: shadok.org/v1 kind: Application
metad### Configuration

Le webhook est configuré via le fichier `webhook.yaml` dans le répertoire
`src/main/kubernetes`. Ce fichier définit :

- La configuration du webhook de mutation
- Le service qui expose le webhook au serveur API Kubernetes

Pour déployer le webhook, vous devez :

1. Générer un certificat TLS pour le webhook
2. Remplacer `${CA_BUNDLE}` dans le fichier `webhook.yaml` par le certificat CA
   encodé en base64
3. Appliquer le fichier `webhook.yaml` à votre cluster Kubernetese:
   my-application namespace: default spec: applicationType: QUARKUS
   projectSourceName: "my-project-source" dependencyCacheName: "maven-cache"
   initContainerMounts: - name: liquibase-changelog mountPath:
   /liquibase/changelog.xml subPath: liquibase/changelog.xml - name:
   application-config mountPath: /config/application.yml subPath:
   config/application.yml labels: app-type: "microservice" team: "backend"

**Note sur `initContainerMounts`** : Ce champ permet de monter des fichiers
spécifiques issus du volume `ProjectSource` dans un `initContainer`, en
utilisant le champ `subPath`. Cela permet par exemple d'injecter un changelog
Liquibase ou des fichiers de configuration sans avoir à créer une `ConfigMap`.

## Vue d'ensemble

L'opérateur Shadok propose trois Custom Resource Definitions (CRDs) principales
:

- **ProjectSource** : Gère les volumes de code source en lecture seule
- **DependencyCache** : Gère les caches de dépendances partagés
- **Application** : Orchestre ProjectSource et DependencyCache selon le type
  d'application

Il inclut également un webhook de mutation pour automatiser l'injection de
volumes dans les Deployments.

## Custom Resource Definitions (CRDs)

### ProjectSource

Le CRD `ProjectSource` permet de créer un PVC (PersistentVolumeClaim) en lecture
seule à partir d'un PV (PersistentVolume) existant avec un chemin spécifique
pour monter les sources d'un projet pour le développement en direct dans
Kubernetes.

#### Spécification

| Champ                  | Description                                                          | Requis | Valeur par défaut |
| ---------------------- | -------------------------------------------------------------------- | ------ | ----------------- |
| `persistentVolumeName` | Nom du PersistentVolume existant                                     | ✅     | -                 |
| `sourcePath`           | Chemin dans le PersistentVolume où se trouvent les sources du projet | ✅     | -                 |
| `pvcName`              | Nom du PersistentVolumeClaim à créer                                 | ✅     | -                 |
| `storageSize`          | Taille de stockage à allouer (ex: "1Gi", "500Mi")                    | ❌     | "1Gi"             |
| `storageClass`         | Classe de stockage pour le PVC                                       | ❌     | "standard"        |
| `accessMode`           | Mode d'accès pour le PVC                                             | ❌     | "ReadOnlyMany"    |
| `labels`               | Labels optionnels à appliquer au PVC créé                            | ❌     | {}                |

```yaml
apiVersion: shadok.org/v1
kind: ProjectSource
metadata:
  name: my-project-source
  namespace: default
spec:
  persistentVolumeName: "dev-sources-pv"
  sourcePath: "/sources/my-app"
  pvcName: "my-app-sources"
  storageSize: "2Gi"
  storageClass: "fast-ssd" # optionnel
  labels:
    environment: "development"
    team: "backend"
```

#### Statut ProjectSource

Le statut du CRD `ProjectSource` indique l'état actuel de la ressource et peut
contenir des informations sur les erreurs éventuelles rencontrées lors de la
création du PVC.

### DependencyCache

Le CRD `DependencyCache` permet de créer un PVC (PersistentVolumeClaim) dédié au
cache des dépendances (comme le répertoire m2 pour Maven) qui peut être partagé
entre plusieurs applications.

#### Spécification DependencyCache

| Champ                  | Description                                                           | Requis | Valeur par défaut |
| ---------------------- | --------------------------------------------------------------------- | ------ | ----------------- |
| `persistentVolumeName` | Nom du PersistentVolume existant                                      | ✅     | -                 |
| `cachePath`            | Chemin dans le PersistentVolume où se trouve le cache des dépendances | ✅     | -                 |
| `pvcName`              | Nom du PersistentVolumeClaim à créer                                  | ✅     | -                 |
| `storageSize`          | Taille de stockage à allouer (ex: "5Gi", "10Gi")                      | ❌     | "5Gi"             |
| `storageClass`         | Classe de stockage pour le PVC                                        | ❌     | "standard"        |
| `accessMode`           | Mode d'accès pour le PVC                                              | ❌     | "ReadWriteMany"   |
| `configMaps`           | Liste des ConfigMaps à monter dans le cache de dépendances            | ❌     | []                |
| `secrets`              | Liste des Secrets à monter dans le cache de dépendances               | ❌     | []                |
| `labels`               | Labels optionnels à appliquer au PVC créé                             | ❌     | {}                |

#### Exemple d'utilisation DependencyCache

```yaml
apiVersion: shadok.org/v1
kind: DependencyCache
metadata:
  name: maven-cache
  namespace: default
spec:
  persistentVolumeName: "dev-cache-pv"
  cachePath: "/cache/m2"
  pvcName: "maven-cache"
  storageSize: "5Gi"
  configMaps:
    - name: maven-settings
      mountPath: "/cache/.m2/settings.xml"
      key: "settings.xml"
  secrets:
    - name: maven-credentials
      mountPath: "/cache/.m2/settings-security.xml"
      key: "settings-security.xml"
  labels:
    cache-type: "maven"
    shared: "true"
```

#### Statut DependencyCache

Le statut du CRD `DependencyCache` indique l'état actuel de la ressource et peut
contenir des informations sur les erreurs éventuelles rencontrées lors de la
création du PVC.

### Application

Le CRD `Application` est une ressource parente qui regroupe les CRDs
`ProjectSource` et `DependencyCache` et ajoute un type d'application. Ce CRD
permet de définir une application complète avec ses sources et son cache de
dépendances.

#### Spécification Application

| Champ                 | Description                                                    | Requis | Types supportés                                             |
| --------------------- | -------------------------------------------------------------- | ------ | ----------------------------------------------------------- |
| `applicationType`     | Type d'application                                             | ✅     | SPRING, QUARKUS, NODE, PYTHON, GO, RUBY, PHP, DOTNET, OTHER |
| `projectSourceName`   | Nom de la ressource ProjectSource à utiliser                   | ✅     | -                                                           |
| `dependencyCacheName` | Nom de la ressource DependencyCache à utiliser                 | ✅     | -                                                           |
| `initContainerMounts` | Liste des points de montage supplémentaires pour initContainer | ❌     | []                                                          |
| `labels`              | Labels optionnels à appliquer aux ressources créées            | ❌     | {}                                                          |

#### Exemple d'utilisation Application

```yaml
apiVersion: shadok.org/v1
kind: Application
metadata:
  name: my-application
  namespace: default
spec:
  applicationType: QUARKUS
  projectSourceName: "my-project-source"
  dependencyCacheName: "maven-cache"
  initContainerMounts:
    - name: liquibase-changelog
      mountPath: /liquibase/changelog.xml
      subPath: liquibase/changelog.xml
```

Le champ `initContainerMounts` permet de monter des fichiers spécifiques issus
du volume `ProjectSource` dans un `initContainer`, en utilisant le champ
`subPath`. Cela permet par exemple d’injecter un changelog Liquibase sans avoir
à créer une `ConfigMap`.

#### Statut

Le statut du CRD `Application` indique l'état actuel de la ressource et contient
des informations sur l'état des ressources ProjectSource et DependencyCache
associées.

## Webhook de Mutation

Le projet inclut également un webhook de mutation pour les Deployments qui
permet d'injecter automatiquement des volumes et des montages de volumes pour
les ConfigMaps et les Secrets associés à une Application.

### Fonctionnement

1. Le webhook intercepte les opérations CREATE et UPDATE sur les ressources
   Deployment
2. Il vérifie si le Deployment contient l'annotation
   `shadok.org/application-name`
3. Si l'annotation est présente, il récupère l'Application correspondante
4. Il récupère ensuite le DependencyCache associé à l'Application
5. Il extrait les ConfigMaps et les Secrets du DependencyCache
6. Il modifie le Deployment pour inclure des volumes et des montages de volumes
   pour ces ConfigMaps et Secrets

### Configuration

Le webhook est configuré via le fichier `webhook.yaml` dans le répertoire
`src/main/kubernetes`. Ce fichier définit:

- La configuration du webhook de mutation
- Le service qui expose le webhook au serveur API Kubernetes

Pour déployer le webhook, vous devez :

1. Générer un certificat TLS pour le webhook
2. Remplacer `${CA_BUNDLE}` dans le fichier `webhook.yaml` par le certificat CA
   encodé en base64
3. Appliquer le fichier `webhook.yaml` à votre cluster Kubernetes

### Utilisation du webhook

Pour utiliser le webhook de mutation, ajoutez simplement l'annotation suivante à
votre Deployment :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  annotations:
    shadok.org/application-name: "my-application"
spec:
  # ... reste de la configuration du Deployment
```

### Détails de la mutation des Pods

🧩 **Mutation du Pod : Résumé global**

L'objectif du webhook est de transformer dynamiquement le Pod pour qu'il :

1. **Monte les sources** (ProjectSource) dans un volume
2. **Monte certains fichiers** de ce volume dans un ou plusieurs initContainers
   (ex: changelog Liquibase)
3. **Remplace le container principal** pour exécuter l'application Java avec un
   mode live-reload

🔧 **Étapes de mutation détaillées**

#### 1. Ajout du volume project-source

Le webhook ajoute automatiquement un volume basé sur le PVC défini dans le
ProjectSource :

```yaml
volumes:
  - name: project-source
    persistentVolumeClaim:
      claimName: my-app-sources # du ProjectSource
      readOnly: true
  - name: dependency-cache
    persistentVolumeClaim:
      claimName: maven-cache # du DependencyCache
      readOnly: false
```

#### 2. Injection des volumeMounts dans les initContainers

Pour chaque élément défini dans `initContainerMounts` de l'Application, le
webhook ajoute des montages spécifiques :

```yaml
initContainers:
  - name: database-migration
    image: liquibase/liquibase:latest
    volumeMounts:
      - name: project-source
        mountPath: /liquibase/changelog.xml
        subPath: liquibase/changelog.xml # fichier spécifique du projet
        readOnly: true
```

#### 3. Transformation du container principal pour le live-reload

Le webhook remplace le container principal pour supporter le développement en
direct :

**Avant mutation (container de production) :**

```yaml
containers:
  - name: app
    image: my-registry/my-app:1.0.0
    ports:
      - containerPort: 8080
```

**Après mutation (container de développement) :**

```yaml
containers:
  - name: app
    image: my-registry/my-app-dev:latest # image avec outils de dev
    command:
      - "mvn"
      - "spring-boot:run" # ou "quarkus:dev" selon le type
    env:
      - name: MAVEN_OPTS
        value: "-Dmaven.repo.local=/cache/.m2/repository"
    volumeMounts:
      - name: project-source
        mountPath: /workspace # sources du projet
        readOnly: true
      - name: dependency-cache
        mountPath: /cache/.m2 # cache Maven partagé
    ports:
      - containerPort: 8080
      - containerPort: 5005 # port debug JVM
    workingDir: /workspace
```

#### 4. Injection des ConfigMaps et Secrets

Le webhook ajoute également les volumes pour les ConfigMaps et Secrets définis
dans le DependencyCache :

```yaml
volumes:
  - name: maven-settings-cm
    configMap:
      name: maven-settings
  - name: maven-credentials-secret
    secret:
      secretName: maven-credentials

# Et les montages correspondants dans le container principal :
volumeMounts:
  - name: maven-settings-cm
    mountPath: /cache/.m2/settings.xml
    subPath: settings.xml
  - name: maven-credentials-secret
    mountPath: /cache/.m2/settings-security.xml
    subPath: settings-security.xml
```

✅ **Résultat final**

- Le Pod exécute directement l'application à partir des sources montées
- Le développement est fluide grâce au live reload
- Les initContainers peuvent accéder à des fichiers du projet sans duplication
  de ressources
- Le cache des dépendances est partagé entre les builds
- Les configurations sont injectées automatiquement

### Paramètres du webhook

- **Timeout** : 5 secondes
- **Failure Policy** : Ignore (n'empêche pas le déploiement en cas d'erreur)
- **Namespaces exclus** : kube-system, kube-public
- **Port** : 8443 (HTTPS)

## Installation et Déploiement

### Prérequis

- Cluster Kubernetes 1.16+
- Permissions pour créer des Custom Resource Definitions
- Permissions pour déployer des webhooks de mutation
- Certificats TLS pour le webhook (auto-générés ou fournis)

### Étapes de déploiement

1. **Construire l'image de l'opérateur** :

   ```bash
   mvn clean package -Dquarkus.container-image.build=true
   ```

2. **Déployer les CRDs** :

   ```bash
   kubectl apply -f target/kubernetes/
   ```

3. **Configurer le webhook** :

   - Générer un certificat TLS ou utiliser cert-manager
   - Remplacer `${CA_BUNDLE}` dans `webhook.yaml`
   - Appliquer la configuration du webhook

4. **Déployer l'opérateur** :

   ```bash
   kubectl apply -f target/kubernetes/
   ```

### Variables d'environnement

L'opérateur peut être configuré via les variables d'environnement suivantes :

| Variable                | Description                   | Valeur par défaut  |
| ----------------------- | ----------------------------- | ------------------ |
| `WEBHOOK_PORT`          | Port d'écoute du webhook      | 8443               |
| `WEBHOOK_TLS_CERT_PATH` | Chemin vers le certificat TLS | `/etc/tls/tls.crt` |
| `WEBHOOK_TLS_KEY_PATH`  | Chemin vers la clé privée TLS | `/etc/tls/tls.key` |
| `LOG_LEVEL`             | Niveau de logging             | INFO               |

## Exemples d'utilisation complète

### Scénario : Application Quarkus avec cache Maven

```yaml
# 1. Créer le ProjectSource
apiVersion: shadok.org/v1
kind: ProjectSource
metadata:
  name: quarkus-project-source
spec:
  persistentVolumeName: "dev-sources-pv"
  sourcePath: "/sources/my-quarkus-app"
  pvcName: "quarkus-sources"
  storageSize: "1Gi"

---
# 2. Créer le DependencyCache
apiVersion: shadok.org/v1
kind: DependencyCache
metadata:
  name: maven-dependency-cache
spec:
  persistentVolumeName: "dev-cache-pv"
  cachePath: "/cache/m2"
  pvcName: "maven-cache"
  storageSize: "5Gi"
  configMaps:
    - name: maven-settings
      mountPath: "/cache/.m2/settings.xml"
      key: "settings.xml"

---
# 3. Créer l'Application
apiVersion: shadok.org/v1
kind: Application
metadata:
  name: my-quarkus-app
spec:
  applicationType: QUARKUS
  projectSourceName: "quarkus-project-source"
  dependencyCacheName: "maven-dependency-cache"
  initContainerMounts:
    - name: database-migration
      mountPath: /migrations/V1__init.sql
      subPath: src/main/resources/db/migration/V1__init.sql

---
# 4. Déploiement utilisant le webhook
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-quarkus-app
  annotations:
    shadok.org/application-name: "my-quarkus-app"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-quarkus-app
  template:
    metadata:
      labels:
        app: my-quarkus-app
    spec:
      containers:
        - name: quarkus-app
          image: my-quarkus-app:latest
          ports:
            - containerPort: 8080
```

## Dépannage

### Problèmes courants

1. **Le webhook ne fonctionne pas** :

   - Vérifiez que le certificat TLS est valide
   - Vérifiez que le service webhook est accessible
   - Consultez les logs de l'opérateur

2. **Les PVCs ne sont pas créés** :

   - Vérifiez que les PVs référencés existent
   - Vérifiez les permissions RBAC
   - Consultez le statut des ressources CRD

3. **Les volumes ne sont pas montés** :
   - Vérifiez l'annotation `shadok.org/application-name` sur le Deployment
   - Vérifiez que l'Application référence les bonnes ressources
   - Consultez les logs du webhook

### Logs et monitoring

```bash
# Consulter les logs de l'opérateur
kubectl logs -l app=shadok -f

# Vérifier le statut des CRDs
kubectl get projectsources,dependencycaches,applications

# Vérifier la configuration du webhook
kubectl get mutatingwebhookconfigurations shadok-deployment-webhook -o yaml
```

### Types d'applications et commandes de live-reload

Le webhook adapte automatiquement la commande de démarrage selon le type
d'application défini dans le CRD `Application` :

| Type d'application | Commande de live-reload                   | Port de debug |
| ------------------ | ----------------------------------------- | ------------- |
| `SPRING`           | `mvn spring-boot:run`                     | 5005          |
| `QUARKUS`          | `mvn quarkus:dev`                         | 5005          |
| `NODE`             | `npm run dev`                             | 9229          |
| `PYTHON`           | `python manage.py runserver 0.0.0.0:8080` | 5678          |
| `GO`               | `go run main.go`                          | 40000         |
| `RUBY`             | `bundle exec rails server`                | 1234          |
| `PHP`              | `php -S 0.0.0.0:8080`                     | 9003          |
| `DOTNET`           | `dotnet watch run`                        | -             |
| `OTHER`            | Configuration manuelle requise            | -             |

**Variables d'environnement ajoutées selon le type :**

- **Java (Spring/Quarkus)** : `MAVEN_OPTS`, `JAVA_TOOL_OPTIONS` pour le debug
- **Node.js** : `NODE_ENV=development`, options d'inspection
- **Python** : `PYTHONPATH`, `DEBUG=True`
- **Go** : Variables pour le mode développement
