# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Shadok is a Kubernetes operator that enables **live development inside the cluster**: pods run source code directly from a shared PVC and reload on change, using a shared dependency cache PVC (e.g. `.m2` for Maven). It is a Quarkus application built with the Java Operator SDK (Fabric8).

## Build, run, test

This is a **Gradle multi-project build** rooted at [build.gradle.kts](build.gradle.kts) (a `java-platform` BOM) with subprojects declared in [settings.gradle.kts](settings.gradle.kts): `:operator` and `pods:quarkus-hello`. Use the root wrapper `./gradlew` — do not `cd` into a subproject.

```bash
# Build everything (applies spotless + runs tests)
./gradlew build

# Build just the operator
./gradlew :operator:build

# Run tests (JUnit Platform)
./gradlew :operator:test

# Run a single test class / method
./gradlew :operator:test --tests org.shadok.operator.model.result.ResourceCheckResultTest
./gradlew :operator:test --tests '*ResourceCheckResultTest.methodName'

# Run the operator in Quarkus dev mode (hot reload)
./gradlew :operator:quarkusDev

# Build + push operator container image (configured in operator/build.gradle.kts via the quarkus block)
./gradlew :operator:build -Dquarkus.container-image.build=true

# Apply code formatting (Google Java Format, Prettier for markdown, shell)
./gradlew spotlessApply

# Check formatting without modifying
./gradlew spotlessCheck
```

Dependency versions and bundles are centralised in `gradle/libs.versions.toml` (version catalog). Prefer `libs.bundles.*` / `libs.*` entries over hard-coded coordinates.

## Deploying to a local Kind cluster

The end-to-end dev loop targets Kind with a local Docker registry on `localhost:5001`.

```bash
# Full deploy (cluster + ingress + registry + CRDs + webhook + operator)
./operator/deploy-to-kind.sh
./operator/deploy-to-kind.sh --verbose
./operator/deploy-to-kind.sh --redeploy-cluster   # wipe + recreate
./operator/deploy-to-kind.sh --no-rebuild --skip-tests

# Validate a running deployment
./operator/test-deployment.sh
./operator/test-deployment.sh status

# Quick rebuild + redeploy after code change (no cluster recreate)
./operator/quick-redeploy.sh

# Standalone webhook TLS test
./test-tls-webhook.sh
```

Defaults: cluster name `shadok-dev`, namespace `shadok`, image `localhost:5001/shadok/operator:latest`. See [operator/DEPLOYMENT.md](operator/DEPLOYMENT.md) for all flags.

## High-level architecture

### Three CRDs, one webhook

The operator exposes three CRDs under `shadok.org/v1`, reconciled independently, and one mutating admission webhook that ties them together at Pod creation time:

- **[ProjectSource](operator/src/main/java/org/shadok/operator/model/code/)** — creates a read-only PVC backed by an existing PV + `sourcePath`. Holds the developer's source tree. Reconciled by [ProjectSourceReconciler](operator/src/main/java/org/shadok/operator/controller/ProjectSourceReconciler.java).
- **[DependencyCache](operator/src/main/java/org/shadok/operator/model/cache/)** — creates a RW PVC for a shared dependency cache (Maven `.m2`, npm, etc.), optionally wiring in ConfigMaps/Secrets (e.g. `settings.xml`). Reconciled by [DependencyCacheReconciler](operator/src/main/java/org/shadok/operator/controller/DependencyCacheReconciler.java).
- **[Application](operator/src/main/java/org/shadok/operator/model/application/)** — references a `ProjectSource` + `DependencyCache` + an `ApplicationType` (SPRING, QUARKUS, NODE, PYTHON, GO, RUBY, PHP, DOTNET, OTHER) and optional `initContainerMounts`. It does **not** create child resources; [ApplicationReconciler](operator/src/main/java/org/shadok/operator/controller/ApplicationReconciler.java) only **validates** that the referenced resources exist and are `READY`, then transitions its own status through `PENDING` / `READY` / `FAILED`. Understand this: Application is a coordination CRD, not an owner of children.
- **[PodMutatingWebhook](operator/src/main/java/org/shadok/operator/webhook/PodMutatingWebhook.java)** (endpoint `POST /mutate-pods`) — the piece that actually makes live dev work. On Pod CREATE, if the pod carries the annotation `org.shadok/application: <name>`, the webhook looks up the `Application`, then the `ProjectSource` + `DependencyCache`, and rewrites the pod to:
  1. Add `project-source` and `dependency-cache` volumes from the referenced PVCs.
  2. Inject `volumeMounts` into matching `initContainers` per `initContainerMounts` (with `subPath` for per-file mounts — e.g. Liquibase changelogs).
  3. Replace the main container's command to use the live-reload command for the `ApplicationType` (`mvn quarkus:dev`, `npm run dev`, etc.), expose the corresponding debug port, and mount the source + cache volumes.
  4. Mount `ConfigMaps`/`Secrets` declared on the `DependencyCache`.

The annotation used by the webhook is `org.shadok/application` (see [PodMutatingWebhook.java:34](operator/src/main/java/org/shadok/operator/webhook/PodMutatingWebhook.java#L34)). Note: the README mentions `shadok.org/application-name` for a deployment-level annotation — the code in `PodMutatingWebhook` is the source of truth for pod mutation.

### Controller / dependent-resource layout

- [controller/](operator/src/main/java/org/shadok/operator/controller/) — one `Reconciler` per CRD. `ProjectSource` and `DependencyCache` use `@Dependent`-style resources in [dependent/](operator/src/main/java/org/shadok/operator/dependent/) (`ProjectSourcePvcDependent`, `DependencyCachePvcDependent`) to create and manage the backing PVCs. `ApplicationReconciler` is **check-only** (no dependents) — it reads the child CRD statuses and reschedules every 15s while pending.
- [model/result/](operator/src/main/java/org/shadok/operator/model/result/) — sealed `ResourceCheckResult<T>` (`Ready` / `NotReady` / `NotFound` / `Failed`) plus a `DependencyState` enum (`BOTH_READY`, `PROJECT_MISSING`, `CACHE_MISSING`, `BOTH_MISSING`). `ApplicationReconciler` uses these in a functional pipeline with `switch` expressions — keep the same style when extending it.
- [model/application/ApplicationTypeHelper.java](operator/src/main/java/org/shadok/operator/model/application/ApplicationTypeHelper.java) — centralises per-`ApplicationType` metadata (build system, cache strategy, live-reload command, debug port, intelligent labels). Add new frameworks here, not scattered across the webhook and reconcilers.

### Quarkus / TLS / webhook wiring

[operator/src/main/resources/application.properties](operator/src/main/resources/application.properties) defines:
- HTTP on `8080`, HTTPS on `8443`, management on `9000`.
- Named TLS config `https` with cert/key mounted at `/tls/tls.crt` and `/tls/tls.key` — the webhook requires a TLS cert; `deploy-to-kind.sh` generates one and patches `${CA_BUNDLE}` into [webhook.yaml](operator/src/main/chart/operator/templates/webhook.yaml).
- `quarkus.operator-sdk.crd.generate=true` — CRDs are generated at build time from the model classes. The generated CRDs land in `operator/build/chart/operator/crds` (see the `copyHelm` task in [operator/build.gradle.kts](operator/build.gradle.kts)) and are packaged into the Helm chart alongside `Chart.yaml` / `values.yaml`.
- `%debug` profile turns on DEBUG logging for `org.shadok.operator.webhook` and `io.javaoperatorsdk.operator`.

### Helm packaging

The operator ships as a Helm chart under [operator/src/main/chart/operator/](operator/src/main/chart/operator/). The `copyHelm` Gradle task template-expands `Chart.yaml` / `values.yaml` with project properties (registry, image name/tag, chart version). Generated CRDs are written into the chart's `crds/` folder during the build, so building the operator also produces a deployable chart.

## Conventions to preserve

- **Java 21** with records, sealed types, pattern-matching `switch`. The reconcilers lean on functional composition (`Function`, `UnaryOperator`, `Optional` chains) — new code in `controller/` and `webhook/` should match this style rather than imperative `if`/`else`.
- **Spotless** enforces Google Java Format (4-space indent) on `src/**/*.java` and Prettier on markdown (80-col, always wrap). Run `./gradlew spotlessApply` before committing or the build will fail.
- French is used in some existing docs and comments; new code comments and logs in the Java sources are in English — follow the file you're editing.
