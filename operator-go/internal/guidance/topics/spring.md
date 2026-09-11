# Spring Boot: DevTools from a volume, keeping the production image

## Recommended sample: keep the production image

The Java sample can use the same production image in both modes. The platform prepares a Kubernetes PVC containing the matching DevTools JAR and mounts it read-only at `/opt/devtools` in the existing application Deployment. The production command does not include that path, so DevTools is not loaded. Shadok preserves this mount and changes the live Java command to include it. No `spec.image` override is needed.

This uses existing volume preservation, not a new operator API. The mount must already be declared in the platform-owned Deployment/chart. Shadok does not create, fill or dynamically attach this PVC. The platform populates it before activation; the synchronization daemon only publishes compiled application outputs afterwards.

From `pods/spring-hello`, on the platform/test-administrator machine:

```sh
mvn verify
docker build --target production -t shadok-spring:local .
kind load docker-image shadok-spring:local --name shadok-go-e2e
# Select the intended namespace/context before the Kubernetes commands.
kubectl -n team-a apply -f kubernetes/devtools-volume.yaml
kubectl -n team-a wait --for=condition=Ready pod/spring-devtools-loader --timeout=120s
kubectl -n team-a cp target/lib/spring-boot-devtools-3.5.6.jar spring-devtools-loader:/devtools/spring-boot-devtools.jar -c loader
kubectl -n team-a exec spring-devtools-loader -c loader -- chmod 0444 /devtools/spring-boot-devtools.jar
kubectl -n team-a delete pod spring-devtools-loader
kubectl -n team-a apply -f kubernetes/production.yaml
kubectl -n team-a rollout status deployment/spring --timeout=120s
kubectl -n team-a apply -f kubernetes/session.yaml
```

These are runnable local sample manifests, not a replacement for your enterprise Helm/Helmfile definitions. For an existing application, add only their PVC/mount configuration to your platform chart and use the application's actual image, namespace and command. On remote clusters replace the local image reference in the application and loader with an accessible registry reference. The loader uses the production image's shell and tar; it is a temporary preparation tool, not the application runtime. The sample needs a default StorageClass and compatible storage permissions; its PVC is ReadWriteOnce, which does not promise multi-node shared access. The platform chooses storage suitable for its topology. Provision the matching DevTools version through your normal artifact process, rather than overwriting a shared live volume during an active session.

The application runs with fsGroup 1000 and mounts the PVC read-only. Its production classpath is `/app/classes:/app/lib/*`. The live session adds `/opt/devtools/*` and omits `spec.image`:

```yaml
apiVersion: shadok.org/v1alpha1
kind: DevelopmentSession
metadata:
  name: spring-live
  namespace: team-a
spec:
  enabled: false
  deployment: spring
  container: app
  runAsUser: 1000
  runAsGroup: 1000
  directories:
    - name: classes
      imagePath: /app/classes
      mountPath: /app/classes
  start:
    command: [java]
    args: [-cp, "/app/classes:/app/lib/*:/opt/devtools/*", example.Application]
    workingDir: /app
```

Enable with the session command below, then use the build/synchronization procedure in this guide. Shadok seeds the writable classes volume from the unchanged production image. The external DevTools PVC is not mounted into the synchronization receiver. Kubernetes replaces pods at activation and restoration; subsequent class updates restart the Spring context inside the JVM, without replacing the pod/container. Disabling restores the production command, which no longer loads DevTools. The platform-owned PVC and its read-only mount remain, as they are part of the original Deployment. Stopping Shadok does not delete platform data.

The live example uses unpacked classes/dependencies and is not an automatic converter for arbitrary executable JAR layouts. Context restart can briefly interrupt requests; it is not zero-downtime JVM hot-swap or parallel A/B routing.

## Alternative: supply a separate live application image

A separate compatible live image is still supported through `spec.image`. In that alternative, the seed reads classes from the selected live image rather than the production image. The following image-build instructions describe that earlier, separately validated path; they are not required for the PVC approach above.

## Prepare the application images

The repository sample `pods/spring-hello` uses Spring Boot 3.5.6, JDK 17+ for compilation, Java 21 images, and Maven. From that directory:

```sh
mvn verify
docker build --target production -t shadok-spring:local .
docker build --target live -t shadok-spring-live:local .
```

Its `production` target is the Dockerfile default and removes `spring-boot-devtools` from `/app/lib`. Its `live` target includes the DevTools dependency copied by Maven. Both have baseline classes under `/app/classes`. Maven is not installed or invoked in the application pod.

For a remote cluster, publish both application images through your normal application pipeline and use their actual registry references. Shadok's own published operator/tools images are not Spring application images. For the dedicated local test cluster, load both sample images:

```sh
kind load docker-image shadok-spring:local shadok-spring-live:local --name shadok-go-e2e
```

The platform deploys `shadok-spring:local` using its existing chart/Helmfile. The example below assumes Deployment `spring`, namespace `team-a`, container `app`, port 8080 and readiness on `/hello`. Adapt these to the actual application. Building/loading images and inspecting Deployments are platform/test-administrator operations; synchronization clients need no Kubernetes credentials.

For another application, build the live image from the matching application revision and compatible dependency versions. Include DevTools and unpacked classes on the live classpath. Do not assume an arbitrary executable JAR has the sample's layout. Preserve required ports, configuration, user permissions and readiness behavior in the live image. Dependency changes require rebuilding that image; this example synchronizes classes and classpath resources only.

## Configure and activate the separate-image alternative

The application chart may create this session. The developer only needs permission to manage the session CR; the operator owns the Deployment changes.

```yaml
apiVersion: shadok.org/v1alpha1
kind: DevelopmentSession
metadata:
  name: spring-live
  namespace: team-a
spec:
  enabled: false
  deployment: spring
  container: app
  image: shadok-spring-live:local
  imagePullPolicy: IfNotPresent
  runAsUser: 1000
  runAsGroup: 1000
  directories:
    - name: classes
      imagePath: /app/classes
      mountPath: /app/classes
  start:
    command: [java]
    args: [-cp, "/app/classes:/app/lib/*", example.Application]
    workingDir: /app
```

Use a registry image reference instead of the local tag on remote clusters. With the Shadok chart, these fields are the corresponding `session.*` values, including `session.image`; session-only releases set `operator.enabled: false`.

```sh
kubectl apply -f session.yaml
kubectl -n team-a patch developmentsession spring-live --type merge -p '{"spec":{"enabled":true}}'
kubectl -n team-a get developmentsession spring-live -o yaml
```

Confirm the status observes the current generation. Ready means the template was applied, not that Spring has started. The platform can check rollout/readiness; the developer should also call the application's normal `/hello` route. DevTools must be enabled on the live classpath; do not carry `spring.devtools.restart.enabled=false` into this runtime.

## Build and synchronize

The sample's committed `shadok.yaml` maps the completed Maven output to the named volume:

```yaml
version: 1
project: spring-hello
groups:
  service:
    mode: build
    roots:
      - mount: classes
        path: target/classes
```

Configure the personal destination as described by `shadok learn configure`: gateway URL, namespace `team-a`, Deployment `spring` (not the session name), and trusted CA if needed. Set `SHADOK_DESTINATION` to that destination. The daemon uses the gateway's `/team-a/spring` route, not the application's HTTP endpoint.

From the sample directory, choose one build integration:

```sh
# The sample POM's profile publishes only after successful verification:
mvn -Pshadok verify

# Or wrap Maven without the publishing profile:
shadok build --config shadok.yaml --group service -- mvn verify
```

Do not combine the publishing profile and wrapper. A failed build publishes nothing. The daemon retains a completed snapshot and synchronizes file additions, changes and deletions. ACK confirms file delivery; call the new/changed HTTP route to confirm Spring reload.

Adding a `@GetMapping` method to a scanned controller or adding a new `@RestController` under the application's component-scan package registers the new route after compilation/sync and DevTools restart. Classes outside component scanning still require the application's usual Spring configuration.

When deleting or renaming sources, Maven can leave stale `.class` files. Use a clean build so the captured output really omits them:

```sh
mvn -Pshadok clean verify
# Alternative without the profile:
shadok build --config shadok.yaml --group service -- mvn clean verify
```

Shadok removes absent files from the synchronized mount, respecting exclusions. It does not infer deletions from Java sources. Do not watch `target/classes` during compilation: publish its completed snapshot instead. The tested removal of a controller deletes its `.class` and makes its former route return 404 after DevTools restarts.

## Return to production

Stop the producer using the same group and destination, then disable the session:

```sh
shadok unwatch --config shadok.yaml --group service
kubectl -n team-a patch developmentsession spring-live --type merge -p '{"spec":{"enabled":false}}'
kubectl -n team-a get developmentsession spring-live -o yaml
```

`unwatch` alone does not restore the Deployment. Confirm the current observed generation and Baseline status, then the normal application response. The platform verifies rollout completion and restoration of the original PodTemplate, including the production image without DevTools. Source changes synchronized during live mode are not written into that image; ship them later through the normal production build/release process. Disable the session before a platform/GitOps application upgrade; restoration deliberately refuses conflicting template changes.

## Live evidence

The repository's `docs/SPRING_VOLUME_VALIDATION.md` records the same-image/PVC scenario. `docs/SPRING_LIVE_VALIDATION.md` records the real Kind test: production container without the DevTools JAR; live-image activation; added controller method and new controller returning 200 after initial 404; controller deletion returning 404; unchanged Pod UID, container ID and restart count across updates; and production restoration. This validates Spring context restart, not browser LiveReload or parallel routing.
