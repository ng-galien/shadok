# Spring Boot: production image to DevTools live mode

## What changes

Shadok does not turn a production JAR into a development runtime or download DevTools. The application team supplies a compatible live image containing Spring Boot DevTools, runtime dependencies and unpacked compiled classes. `DevelopmentSession.spec.image` selects that image; `spec.start` selects its Java command.

1. The platform's existing Deployment runs the production image without DevTools.
2. Enabling the session makes the operator save the original PodTemplate, select the live image and command, and add the shared volumes and synchronization receiver. Kubernetes rolls out replacement pods once for this activation.
3. The seed init container uses the **selected live image**, copies its `/app/classes` into an emptyDir, then the application mounts that volume at `/app/classes`. Libraries stay in `/app/lib` in the live image. The seed does not extract files from the old running production pod.
4. Successful builds on the workstation or CI runner publish compiled classes into that volume. DevTools detects classpath changes and restarts the Spring context inside the JVM. These updates do not require rebuilding the image or replacing the pod/container.
5. Disabling the session restores the saved production image, command and PodTemplate through another rollout.

This is the current replacement mode, not a parallel A/B workload. Application-context restart can briefly interrupt requests; it is not zero-downtime JVM hot-swap.

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

## Configure and activate

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

The repository's `docs/SPRING_LIVE_VALIDATION.md` records the real Kind test: production container without the DevTools JAR; live-image activation; added controller method and new controller returning 200 after initial 404; controller deletion returning 404; unchanged Pod UID, container ID and restart count across updates; and production restoration. This validates Spring context restart, not browser LiveReload or parallel routing.
