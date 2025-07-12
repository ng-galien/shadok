# 📏 Conventions de codage – Java 21 + Java Operator SDK

Ce document définit les bonnes pratiques de codage pour un projet basé sur **Java 21** et le **Java Operator SDK**, en tirant parti des dernières fonctionnalités du langage (threads virtuels, record patterns...) et du SDK (workflows, ressources dépendantes).

---

## 🛠️ 1. Structure du projet

### 1.1 Organisation modulaire Gradle

Le répertoire `src` doit être contenu dans un module Gradle pour une meilleure organisation et gestion des dépendances :

```text
module/
├── build.gradle.kts
├── src/
│   ├── main/
│   │   ├── java/
│   │   │   └── org.shadok.operator/
│   │   │       ├── controller/         # Reconcilers
│   │   │       ├── dependent/          # DependentResources
│   │   │       ├── workflow/           # Workflows JOSDK
│   │   │       ├── model/              # CRD spec/status
│   │   │       ├── webhook/            # Admission webhooks
│   │   │       ├── util/               # Utilitaires
│   │   │       └── config/             # Configuration
│   │   ├── resources/
│   │   │   ├── application.properties
│   │   │   └── kubernetes/             # Manifests K8s
│   │   └── docker/                     # Dockerfiles
│   └── test/
│       ├── java/                       # Tests unitaires
│       └── resources/                  # Resources de test
```

### 1.2 Répartition des responsabilités

- **`controller/`** : Reconcilers et enregistrement JOSDK
- **`dependent/`** : Ressources dépendantes (PVC, Deployment, ConfigMap)
- **`workflow/`** : Définition des workflows JOSDK
- **`model/`** : Classes CRD spec/status annotées
- **`webhook/`** : Admission et validation webhooks
- **`util/`**, **`config/`** : Utilitaires et configuration

---

## 🌐 2. Style de codage Java 21

### 2.1 Nommage

Se conformer aux conventions Sun/Oracle :

- Classes, interfaces, enums → `UpperCamelCase`
- Méthodes, attributs, variables locales → `lowerCamelCase`
- Constantes → `SCREAMING_SNAKE_CASE`
- Packages → `lowercase.dot.separated`

**Conventions spécifiques aux opérateurs :**

```java
// CRD et ressources
public class ApplicationReconciler { }
public class CachePvcDependent { }

// Records pour DTOs
record PodReference(String name, String namespace) { }

// Constantes d'annotations et labels
private static final String ANNOTATION_APP_CONFIG = "org.shadok/application";
private static final String LABEL_MANAGED_BY = "app.kubernetes.io/managed-by";
```

### 2.2 Format et Style

- **Indentation** : 4 espaces
- **Longues conditions** : opérateur en début de ligne
- **Longues chaînes de paramètres** : indentation de 8 espaces
- **Accolades** : style K&R (opening brace sur la même ligne)

```java
// Exemple de formatage pour les longues conditions
if (condition1
        && condition2
        || condition3) {
    // action
}

// Paramètres multiples
public void createResource(
        String name,
        String namespace,
        Map<String, String> labels,
        ApplicationSpec spec) {
    // implementation
}
```

### 2.3 Documentation et Commentaires

- **Javadoc** obligatoire pour les classes publiques et méthodes d'API
- **Commentaires inline** pour la logique métier complexe
- **TODO/FIXME** avec ticket de suivi
- **Langue** : Tous les commentaires et documentation doivent être **rédigés en anglais**

```java
/**
 * Reconcile application resources in Kubernetes cluster.
 * 
 * @param application the application CRD to reconcile
 * @param context reconciliation context with secondary resources
 * @return update control indicating next reconciliation action
 */
@Override
public UpdateControl<Application> reconcile(Application application, Context<Application> context) {
    // TODO: Add retry logic for failed deployments (SHADOK-123)
    return handleReconciliation(application, context);
}
```

---

## ✨ 3. Usage des nouveautés Java 21

### 3.1 Record Patterns

Utiliser les **record patterns** pour le traitement de données :

```java
record ApplicationState(Status status, String message) {}

void handleApplicationState(Object state) {
    switch (state) {
        case ApplicationState(Status.READY, var msg) -> log.info("App ready: {}", msg);
        case ApplicationState(Status.FAILED, var error) -> log.error("App failed: {}", error);
        case ApplicationState(var status, _) -> log.debug("App status: {}", status);
    }
}
```

### 3.2 Pattern Matching dans switch

```java
public UpdateControl<Application> handleStatus(Application app) {
    return switch (app.getStatus().getState()) {
        case READY -> UpdateControl.noUpdate();
        case PENDING -> UpdateControl.<Application>noUpdate().rescheduleAfter(Duration.ofSeconds(5));
        case FAILED -> {
            app.getStatus().setMessage("Reconciliation failed, retrying...");
            yield UpdateControl.patchStatus(app);
        }
    };
}
```

### 3.3 Threads virtuels

Préférer les virtual threads pour les appels bloquants :

```java
@ApplicationScoped
public class AsyncOperations {
    
    public CompletableFuture<Void> processInBackground(List<Pod> pods) {
        try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
            return CompletableFuture.allOf(
                pods.stream()
                    .map(pod -> CompletableFuture.runAsync(() -> processPod(pod), executor))
                    .toArray(CompletableFuture[]::new)
            );
        }
    }
}
```

### 3.4 Nouveautés Java 21 spécifiques

**Séquences et collections modernes :**

```java
// Utiliser SequencedCollection.reversed() pour itération inverse
List<String> dependencies = getDependencies();
for (String dep : dependencies.reversed()) {
    cleanup(dep); // Nettoyage dans l'ordre inverse
}

// Pour bornage de valeur, utiliser Math.clamp()
int replicas = Math.clamp(spec.getReplicas(), 1, 10);
```

**String Templates (Preview) :**

```java
// Utiliser avec parcimonie, uniquement pour le logging/debug
String logMessage = STR."Processing pod \{podName} in namespace \{namespace}";
log.info(logMessage);
```

### 3.5 Style fonctionnel

**Préférer la composition de fonctions** pour créer des pipelines de traitement lisibles et maintenables :

```java
public class PodMutatingWebhook {
    
    // Déclarer les fonctions comme des attributs de classe pour la réutilisabilité
    private final Predicate<Operation> isCreateOp = op -> op == Operation.CREATE;
    
    private final Function<Pod, Optional<CrdRef>> findAnnotation = pod ->
        Optional.ofNullable(pod)
            .flatMap(p -> Optional.ofNullable(p.getMetadata()))
            .flatMap(meta -> Optional.ofNullable(meta.getAnnotations()))
            .flatMap(annotations ->
                Optional.ofNullable(annotations.get(ANNOTATION_CONFIG)))
            .filter(name -> !name.isEmpty())
            .map(name -> new CrdRef(name, pod.getMetadata().getNamespace()));
}
```

**Chaîner les opérations avec Optional** pour éviter les vérifications null explicites :

```java
private AdmissionController<Pod> admissionController() {
    return new AdmissionController<>(
        (pod, operation) -> Optional.of(operation)
            .filter(isCreateOp)
            .flatMap(op -> findAnnotation.apply(pod))
            .flatMap(findAppSpec(client))
            .map(mutateOp)
            .map(mutator -> mutator.apply(pod))
            .orElse(pod)
    );
}
```

**Utiliser des records pour les DTOs internes** :

```java
record CrdRef(String name, String namespace) {}
record ReconciliationResult(boolean success, String message, Duration nextReconcile) {}
```

### 3.6 ADT avec Sealed Interfaces

**Utiliser des sealed interfaces** pour modéliser des types de données algébriques (ADT) qui représentent un ensemble fini et fermé de cas :

```java
// Définition de l'ADT pour l'état d'une reconciliation
public sealed interface ReconciliationState 
    permits ReconciliationState.Pending, 
            ReconciliationState.InProgress, 
            ReconciliationState.Success, 
            ReconciliationState.Failed {
    
    record Pending(String reason) implements ReconciliationState {}
    record InProgress(String phase, int stepCount, int currentStep) implements ReconciliationState {}
    record Success(String message, Instant completedAt) implements ReconciliationState {}
    record Failed(String error, Throwable cause, boolean retryable) implements ReconciliationState {}
}
```

**Pattern matching exhaustif** avec switch expressions :

```java
public UpdateControl<Application> handleReconciliationState(
        Application app, 
        ReconciliationState state) {
    
    return switch (state) {
        case ReconciliationState.Pending(var reason) -> {
            app.getStatus().setMessage(STR."Pending: \{reason}");
            yield UpdateControl.patchStatus(app).rescheduleAfter(Duration.ofSeconds(5));
        }
        
        case ReconciliationState.InProgress(var phase, var total, var current) -> {
            var progress = STR."\{current}/\{total}";
            app.getStatus().setMessage(STR."Processing \{phase} (\{progress})");
            yield UpdateControl.patchStatus(app).rescheduleAfter(Duration.ofSeconds(2));
        }
        
        case ReconciliationState.Success(var message, var completedAt) -> {
            app.getStatus().setState(ApplicationStatus.State.READY);
            app.getStatus().setMessage(message);
            app.getStatus().setLastReconciled(completedAt);
            yield UpdateControl.patchStatus(app);
        }
        
        case ReconciliationState.Failed(var error, var cause, var retryable) -> {
            app.getStatus().setState(ApplicationStatus.State.FAILED);
            app.getStatus().setMessage(STR."Failed: \{error}");
            
            if (retryable) {
                // Retry avec backoff exponentiel
                yield UpdateControl.patchStatus(app)
                    .rescheduleAfter(Duration.ofMinutes(1));
            } else {
                // Erreur non récupérable
                yield UpdateControl.patchStatus(app);
            }
        }
    };
}
```

**ADT pour les événements métier** :

```java
public sealed interface ApplicationEvent permits 
    ApplicationEvent.Created,
    ApplicationEvent.SpecChanged,
    ApplicationEvent.StatusUpdated,
    ApplicationEvent.Deleted {
    
    record Created(Application application, Instant timestamp) implements ApplicationEvent {}
    record SpecChanged(Application application, ApplicationSpec oldSpec, ApplicationSpec newSpec) implements ApplicationEvent {}
    record StatusUpdated(Application application, ApplicationStatus oldStatus, ApplicationStatus newStatus) implements ApplicationEvent {}
    record Deleted(String name, String namespace, Instant timestamp) implements ApplicationEvent {}
}

// Traitement des événements avec pattern matching
public void handleEvent(ApplicationEvent event) {
    switch (event) {
        case ApplicationEvent.Created(var app, var timestamp) -> {
            log.info("Application created: {} at {}", app.getMetadata().getName(), timestamp);
            metrics.incrementCounter("application.created");
        }
        
        case ApplicationEvent.SpecChanged(var app, var oldSpec, var newSpec) -> {
            log.info("Application spec changed: {}", app.getMetadata().getName());
            auditLog.recordChange(app, oldSpec, newSpec);
        }
        
        case ApplicationEvent.StatusUpdated(var app, var oldStatus, var newStatus) -> {
            if (oldStatus.getState() != newStatus.getState()) {
                notificationService.notifyStateChange(app, oldStatus.getState(), newStatus.getState());
            }
        }
        
        case ApplicationEvent.Deleted(var name, var namespace, var timestamp) -> {
            log.info("Application deleted: {}/{} at {}", namespace, name, timestamp);
            cleanupService.cleanupResources(name, namespace);
        }
    }
}
```

**ADT pour les opérations asynchrones** :

```java
public sealed interface AsyncOperation<T> permits 
    AsyncOperation.NotStarted,
    AsyncOperation.Running,
    AsyncOperation.Completed,
    AsyncOperation.Cancelled {
    
    record NotStarted<T>() implements AsyncOperation<T> {}
    record Running<T>(String operationId, Instant startedAt) implements AsyncOperation<T> {}
    record Completed<T>(T result, Duration executionTime) implements AsyncOperation<T> {}
    record Cancelled<T>(String reason) implements AsyncOperation<T> {}
    
    // Méthodes utilitaires
    default boolean isCompleted() {
        return this instanceof Completed<T>;
    }
    
    default Optional<T> getResult() {
        return switch (this) {
            case Completed<T>(var result, _) -> Optional.of(result);
            default -> Optional.empty();
        };
    }
}
```

**Avantages des ADT avec sealed interfaces :**

- **Exhaustivité** : Le compilateur garantit que tous les cas sont traités
- **Type safety** : Pas de casting ou de vérifications instanceof manuelles
- **Lisibilité** : Code déclaratif et expressif
- **Maintenabilité** : Ajouter un nouveau cas force la mise à jour de tous les switch
- **Performance** : Pattern matching optimisé par la JVM

### 3.7 Gestion des erreurs et exceptions

**Préférer les types Optional** pour les valeurs potentiellement absentes :

```java
public Optional<ApplicationSpec> findApplicationSpec(String name, String namespace) {
    return Optional.ofNullable(client
        .resources(Application.class)
        .inNamespace(namespace)
        .withName(name)
        .get())
        .map(Application::getSpec);
}
```

**Utiliser des exceptions spécifiques** pour les erreurs métier :

```java
public class ReconciliationException extends RuntimeException {
    private final String resourceName;
    private final String namespace;
    
    public ReconciliationException(String message, String resourceName, String namespace, Throwable cause) {
        super(STR."[\{namespace}/\{resourceName}] \{message}", cause);
        this.resourceName = resourceName;
        this.namespace = namespace;
    }
}

// Usage dans le reconciler
try {
    deployApplication(spec);
} catch (KubernetesClientException e) {
    throw new ReconciliationException(
        "Failed to deploy application", 
        application.getMetadata().getName(),
        application.getMetadata().getNamespace(),
        e
    );
}
```

**Pattern Result pour la gestion d'erreurs explicite** :

```java
public sealed interface Result<T> permits Success, Failure {
    record Success<T>(T value) implements Result<T> {}
    record Failure<T>(String error, Throwable cause) implements Result<T> {}
    
    static <T> Result<T> success(T value) { return new Success<>(value); }
    static <T> Result<T> failure(String error, Throwable cause) { 
        return new Failure<>(error, cause); 
    }
    
    default <U> Result<U> map(Function<T, U> mapper) {
        return switch (this) {
            case Success<T>(var value) -> success(mapper.apply(value));
            case Failure<T>(var error, var cause) -> failure(error, cause);
        };
    }
}
```

---

## 🧭 4. Bonnes pratiques Java Operator SDK

### 4.1 Reconcilers

**Structure de base d'un Reconciler :**

```java
@ControllerConfiguration(
    name = "application-controller",
    informer = @Informer(namespaces = WATCH_CURRENT_NAMESPACE)
)
@Workflow(dependents = {
    @Dependent(type = ConfigMapDependent.class),
    @Dependent(type = DeploymentDependent.class),
    @Dependent(type = ServiceDependent.class, readyPostcondition = ServiceDependent.class)
})
public class ApplicationReconciler implements Reconciler<Application>, ContextInitializer<Application> {

    private static final Logger log = LoggerFactory.getLogger(ApplicationReconciler.class);
    
    @Override
    public void initContext(Application application, Context<Application> context) {
        // Initialiser le contexte partagé entre les dependent resources
        var labels = createLabels(application);
        context.managedWorkflowAndDependentResourceContext().put("labels", labels);
    }
    
    @Override
    public UpdateControl<Application> reconcile(Application application, Context<Application> context) {
        var name = application.getMetadata().getName();
        log.info("Reconciling application: {}", name);
        
        // Vérifier l'état des ressources dépendantes
        var workflowResult = context.managedWorkflowAndDependentResourceContext()
            .getWorkflowReconcileResult();
            
        return workflowResult
            .filter(WorkflowReconcileResult::allDependentResourcesReady)
            .map(wrs -> {
                // Toutes les ressources sont prêtes
                application.setStatus(createReadyStatus());
                log.info("Application {} is ready", name);
                return UpdateControl.patchStatus(application);
            })
            .orElseGet(() -> {
                // Attendre que les ressources soient prêtes
                log.info("Application {} is not ready yet, rescheduling", name);
                return UpdateControl.<Application>noUpdate()
                    .rescheduleAfter(Duration.ofSeconds(10));
            });
    }
}
```

**Bonnes pratiques pour les Reconcilers :**

- Toujours comparer l'état voulu vs réel, même sans événement pertinent
- Utiliser les EventSources pour watcher les ressources dépendantes
- Implémenter une logique de retry avec backoff exponentiel
- Logger les actions importantes avec des niveaux appropriés
- Gérer les cas d'erreur avec des status explicites

### 4.2 Dependent Resources

**Structure de base d'une DependentResource :**

```java
@Component
public class DeploymentDependent extends CRUDKubernetesDependentResource<Deployment, Application> {

    public DeploymentDependent() {
        super(Deployment.class);
    }
    
    @Override
    protected Deployment desired(Application application, Context<Application> context) {
        var labels = (Map<String, String>) context.managedWorkflowAndDependentResourceContext()
            .get("labels");
            
        return new DeploymentBuilder()
            .withMetadata(createMetadata(application, labels))
            .withSpec(createDeploymentSpec(application))
            .build();
    }
    
    @Override
    public Result<Deployment> match(Deployment actualResource, Application primary, Context<Application> context) {
        var desired = desired(primary, context);
        
        // Comparer les specs importantes (sans les champs générés par K8s)
        if (Objects.equals(actualResource.getSpec().getReplicas(), desired.getSpec().getReplicas())
                && Objects.equals(actualResource.getSpec().getTemplate(), desired.getSpec().getTemplate())) {
            return Result.nonMatching();
        }
        
        return Result.matched();
    }
}
```

### 4.3 Workflows et orchestration

**Définir des dépendances complexes :**

```java
@Workflow(dependents = {
    @Dependent(name = "configmap", type = ConfigMapDependent.class),
    @Dependent(
        name = "deployment", 
        type = DeploymentDependent.class,
        dependsOn = {"configmap"}
    ),
    @Dependent(
        name = "service", 
        type = ServiceDependent.class,
        dependsOn = {"deployment"},
        readyPostcondition = ServiceReadyCondition.class
    )
})
```

**Conditions personnalisées :**

```java
public class ServiceReadyCondition implements Condition<Service, Application> {
    @Override
    public boolean met(DependentResource<Service, Application> dependentResource,
                      Application primary,
                      Context<Application> context) {
        return dependentResource.getSecondaryResource(primary, context)
            .map(service -> service.getSpec().getClusterIP() != null)
            .orElse(false);
    }
}
```

### 4.4 Tests et validation

**Tests unitaires pour les Reconcilers :**

```java
@ExtendWith(MockitoExtension.class)
class ApplicationReconcilerTest {
    
    @Mock
    private KubernetesClient client;
    
    @InjectMocks
    private ApplicationReconciler reconciler;
    
    @Test
    void shouldUpdateStatusWhenAllResourcesReady() {
        // Given
        var application = createTestApplication();
        var context = createMockContext(true); // all resources ready
        
        // When
        var result = reconciler.reconcile(application, context);
        
        // Then
        assertThat(result.isUpdateStatus()).isTrue();
        assertThat(application.getStatus().getState()).isEqualTo(State.READY);
    }
}
```

**Tests d'intégration avec Testcontainers :**

```java
@QuarkusTest
@Testcontainers
class ApplicationReconcilerIT {
    
    @Container
    static K3sContainer k3s = new K3sContainer(DockerImageName.parse("rancher/k3s:latest"));
    
    @Test
    void shouldReconcileApplicationSuccessfully() {
        // Test avec un vrai cluster Kubernetes
    }
}
```

### 4.5 Style et contribution

**Formatage et style :**

- Suivre le style Google Java (formatage automatique via `google-java-format`)
- Utiliser des imports statiques pour les builders K8s courants
- Organiser les imports par groupes logiques

**Git et CI/CD :**

- Commits selon conventional commits format
- Intégration continue avec formatage et tests obligatoires
- Pre-commit hooks pour validation du style

```java
// Imports statiques recommandés
import static io.fabric8.kubernetes.api.model.LabelSelectorBuilder;
import static io.javaoperatorsdk.operator.api.reconciler.UpdateControl.noUpdate;
import static io.javaoperatorsdk.operator.api.reconciler.UpdateControl.patchStatus;
```

---

## 🎯 5. Exemples complets

### 5.1 Reconciler minimal avec style fonctionnel

```java
@ControllerConfiguration(name = "cache-controller")
@Workflow(dependents = @Dependent(type = CachePvcDependent.class))
public class CacheReconciler implements Reconciler<DependencyCache> {

    private static final Logger log = LoggerFactory.getLogger(CacheReconciler.class);
    
    // Style fonctionnel pour les transformations
    private final Function<DependencyCache, UpdateControl<DependencyCache>> reconcileLogic = cache -> 
        Optional.of(cache)
            .filter(this::isSpecValid)
            .map(this::processCache)
            .map(this::updateStatus)
            .orElseGet(() -> this.handleInvalidSpec(cache));
    
    @Override
    public UpdateControl<DependencyCache> reconcile(DependencyCache cache, Context<DependencyCache> context) {
        return reconcileLogic.apply(cache);
    }
    
    private boolean isSpecValid(DependencyCache cache) {
        return cache.getSpec() != null && cache.getSpec().getSize() != null;
    }
    
    private DependencyCache processCache(DependencyCache cache) {
        log.info("Processing cache: {}", cache.getMetadata().getName());
        // Logique métier
        return cache;
    }
    
    private UpdateControl<DependencyCache> updateStatus(DependencyCache cache) {
        cache.setStatus(new DependencyCacheStatus(State.READY, "Cache is ready"));
        return patchStatus(cache);
    }
    
    private UpdateControl<DependencyCache> handleInvalidSpec(DependencyCache cache) {
        cache.setStatus(new DependencyCacheStatus(State.FAILED, "Invalid specification"));
        return patchStatus(cache);
    }
}
```

Cette version revisée des conventions apporte :

## ✅ **Améliorations apportées :**

1. **Structure claire** - Organisation modulaire avec répartition des responsabilités
2. **Java 21 moderne** - Usage des dernières fonctionnalités (records, pattern matching, virtual threads)
3. **Style fonctionnel** - Composition de fonctions, Optional, immutabilité
4. **Gestion d'erreurs robuste** - Exceptions typées, pattern Result
5. **Tests complets** - Exemples unitaires et d'intégration
6. **Exemples concrets** - Code réel applicable directement
7. **Bonnes pratiques JOSDK** - Workflows, dependent resources, conditions
8. **Documentation complète** - Javadoc, commentaires, formatting

Le fichier est maintenant beaucoup plus complet et utilisable comme référence pour le développement d'opérateurs Kubernetes modernes en Java 21.
