# Put an existing Quarkus JVM application into live mode

## 1. Prerequisites and files to create

Work in the application's repository. Keep its deployed production image, chart, environment and routing. The platform must have installed Shadok and supplied a reachable sync gateway. You need the source revision and dependencies matching the image, its Java/Quarkus versions, and a working Maven or Gradle build.

This procedure retains the production **fast-jar image and application JAR**. Shadok copies that image's application directory into its working emptyDir. A separate read-only volume supplies only Quarkus's matching deployment libraries and model. Quarkus's official bootstrap extracts the application's reloadable files inside the pod.

Create these files in your application repository:

| File | Purpose |
| --- | --- |
| `live/tools-volume.yaml` | Framework-only resource storage and temporary loader |
| `live/session.yaml` | Target, live directory and startup command |
| Gradle `stageShadok` task **or** Maven staging commands below | Place compiled application files at `dev/app/` in the local mirror |

An agent restricted to DevelopmentSessions obtains image/layout information and matching framework resources from the platform. It supplies the volume/mount files to the platform; it does not need broader permissions to publish builds.

## 2. Inspect the production image

Set the target values and obtain the rendered Deployment from the platform, or read it if allowed:

```sh
export CONTEXT=YOUR_CONTEXT
export NAMESPACE=YOUR_APPLICATION_NAMESPACE
export DEPLOYMENT=YOUR_EXISTING_DEPLOYMENT
export IMAGE=YOUR_IMMUTABLE_PRODUCTION_IMAGE
export SYNC_URL=https://YOUR_SYNC_GATEWAY
export SYNC_CA="" # Set an absolute PEM CA path only for a private gateway CA.
export APP_URL=https://YOUR_APPLICATION_HOST
kubectl --context "$CONTEXT" -n "$NAMESPACE" get deployment "$DEPLOYMENT" -o yaml
docker pull "$IMAGE"
docker image inspect "$IMAGE"
mkdir -p live/inspect
CONTAINER_ID=$(docker create "$IMAGE")
# Replace /deployments with the application directory found in the image configuration.
docker cp "$CONTAINER_ID:/deployments" live/inspect/production
docker rm "$CONTAINER_ID"
```

Record the container name, runtime UID/GID, Java version, startup options, application port, probes, mounted configuration and exact Quarkus platform version. Inspect the copied files:

| Layout | Action |
| --- | --- |
| `quarkus-run.jar`, `app/`, `lib/`, `quarkus/` | JVM fast-jar: use this procedure |
| Same layout with `lib/deployment/` | Check whether it is already a matching mutable-jar; do not assume it from directory names alone |
| Uber JAR | Build a matching mutable-jar from the project's build; do not treat the single JAR as a mutable application |
| Native executable or an image without a compatible JVM | Supply an explicitly selected JVM runtime/image before using this procedure; a native binary cannot execute this JVM dev mode |

The live command below requires `sh`, `cp` and Java in the application image. Verify those executables. Preserve the actual application's JVM options, port and configuration. Select a writable mount path that does not collide with existing mounts. Replace `/deployments`, `/live/quarkus`, UID/GID `185` and other placeholders below with the inspected values.

## 3. Prepare framework resources — platform / application build pipeline

A fast-jar does not contain the deployment-time model used by Quarkus remote dev. Supply those **framework resources**, matched to the same Quarkus version, extension/dependency graph and application coordinates. This is not a generic JAR interchangeable across unrelated applications.

The build pipeline produces these resources using Quarkus's supported mutable packaging. Use an existing matching mutable build artifact when available. To produce it with the project's existing build tooling:

```sh
# Maven, from the application module:
./mvnw package -Dquarkus.package.jar.type=mutable-jar \
  -Dquarkus.container-image.build=false -Dquarkus.container-image.push=false
export QUARKUS_OUTPUT="$PWD/target/quarkus-app"
```

Gradle alternative:

```sh
./gradlew quarkusBuild -Dquarkus.package.jar.type=mutable-jar \
  -Dquarkus.container-image.build=false -Dquarkus.container-image.push=false
export QUARKUS_OUTPUT="$PWD/build/quarkus-app"
```

These commands generate Quarkus's model and deployment tooling using the project's build. **The resulting application JAR/classes are not deployed or uploaded.** The live application will still come from the existing production image. Do not present this resource-generation step as something a bare fast-jar can provide by itself.

Create a fresh resource bundle containing exactly:

```sh
mkdir -p live/quarkus-tools/lib live/quarkus-tools/quarkus
cp -R "$QUARKUS_OUTPUT/lib/deployment" live/quarkus-tools/lib/
cp "$QUARKUS_OUTPUT/quarkus/build-system.properties" live/quarkus-tools/quarkus/
```

Bundle layout:

```text
quarkus-tools/
  lib/deployment/                 # Quarkus deployment dependencies and model files
  quarkus/build-system.properties # Quarkus build-time configuration
```

Do not copy `app/`, `dev/`, `quarkus-run.jar`, generated/transformed application bytecode or the entire mutable directory. Associate this bundle with the production image/build identity and verify application coordinates in its model match the application JAR name in the image. Do not reuse an old bundle after changing extensions or dependencies.

## 4. Mount only these framework resources — platform operation

Create `live/tools-volume.yaml`, replacing namespace, runtime IDs and approved loader image (`sh` and `tar` required):

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: quarkus-reload-tools
  namespace: APPLICATION_NAMESPACE
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 256Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: quarkus-reload-tools-loader
  namespace: APPLICATION_NAMESPACE
spec:
  securityContext:
    runAsUser: 185
    runAsGroup: 185
    fsGroup: 185
  containers:
    - name: loader
      image: APPROVED_IMAGE_WITH_SH_AND_TAR
      command: [sh, -c, "sleep 3600"]
      volumeMounts:
        - name: tools
          mountPath: /tools
  volumes:
    - name: tools
      persistentVolumeClaim:
        claimName: quarkus-reload-tools
```

Adjust storage capacity to the bundle size and choose an access mode compatible with replica placement. Concurrent ReadWriteOnce mounts require the same node. Populate a fresh volume:

```sh
kubectl --context "$CONTEXT" apply -f live/tools-volume.yaml
kubectl --context "$CONTEXT" -n "$NAMESPACE" wait \
  --for=condition=Ready pod/quarkus-reload-tools-loader --timeout=120s
kubectl --context "$CONTEXT" -n "$NAMESPACE" cp \
  live/quarkus-tools/. quarkus-reload-tools-loader:/tools
kubectl --context "$CONTEXT" -n "$NAMESPACE" delete pod quarkus-reload-tools-loader
```

Declare the PVC in the DevelopmentSession below. The operator adds and removes its mount; do not patch the application Deployment.

## 5. Define the live session and local mirror

Create `live/session.yaml`:

```yaml
apiVersion: shadok.org/v1alpha1
kind: DevelopmentSession
metadata:
  name: quarkus-live
  namespace: APPLICATION_NAMESPACE
spec:
  enabled: false
  deployment: EXISTING_DEPLOYMENT
  container: APPLICATION_CONTAINER
  runAsUser: 185
  runAsGroup: 185
  directories:
    - name: application
      imagePath: /deployments
      mountPath: /live/quarkus
      localPath: build/shadok-sync
      exclude: [lib, 'lib/**', app, 'app/**', quarkus, 'quarkus/**', '*.jar', quarkus-app-dependencies.txt]
  volumes:
    - name: quarkus-tools
      mountPath: /opt/quarkus-reload
      readOnly: true
      persistentVolumeClaim:
        claimName: quarkus-reload-tools
        readOnly: true
  start:
    command: [sh]
    args:
      - -ec
      - |
        cp -R /opt/quarkus-reload/lib/deployment /live/quarkus/lib/
        cp /opt/quarkus-reload/quarkus/build-system.properties /live/quarkus/quarkus/
        export QUARKUS_LAUNCH_DEVMODE=true
        exec java -Dquarkus.http.host=0.0.0.0 -Dquarkus.profile=prod -Dquarkus.console.enabled=false -jar /live/quarkus/quarkus-run.jar
    workingDir: /live/quarkus
```

No `spec.image` override is set. Shadok seeds the complete directory from the existing production image. The startup command adds only the framework resources, retaining the original application JAR and runner. `QUARKUS_LAUNCH_DEVMODE` selects Quarkus remote server mode. `quarkus.profile=prod` retains the normal profile's configuration while enabling live coding; select your application's actual configuration profile and preserve its required JVM options. Quarkus's own bootstrap prepares `dev/app`.

The session uses `localPath: build/shadok-sync` for Gradle. For Maven use `localPath: target/shadok-sync`. These paths are relative to the CLI working directory; the gateway supplies the mapping and exclusions, so no local YAML or group is required.

The mirror contains `dev/app/...` only. **Keep these exclusions**: they prevent synchronization from deleting bootstrap libraries, packaged application JARs and Quarkus metadata absent from the compiler output. Check additional files in your actual package and exclude runtime-owned paths too. Do not exclude `dev/app`, where class deletions must propagate.

For multi-module applications, Quarkus also prepares reloadable module directories under `dev/<groupId>/<artifactId>`. Identify them in that version's mutable application and stage each module's outputs at the corresponding path. The single-module mapping above does not automatically cover other modules.

## 6. Compile and publish — choose your build tool

### Gradle

Add this task to the application module's `build.gradle.kts`:

```kotlin
tasks.register<Sync>("stageShadok") {
    dependsOn(tasks.named("classes"), tasks.named("test"))
    from(sourceSets.main.get().output)
    into(layout.buildDirectory.dir("shadok-sync/dev/app"))
}
```

This is Gradle's standard `Sync` task: it copies compiled classes/resources into the mirror and removes stale staged files. It does not contact Kubernetes. After activation in chapter 7, run:

```sh
shadok build --session "$NAMESPACE/quarkus-live" \
  --url "$SYNC_URL" --ca-file "$SYNC_CA" \
  -- ./gradlew clean stageShadok
```

### Maven

No profile is required. After activation, execute these steps from the application module in a stop-on-error shell/CI job:

```sh
set -e
./mvnw clean verify -Dquarkus.container-image.build=false -Dquarkus.container-image.push=false
mkdir -p target/shadok-sync/dev/app
cp -R target/classes/. target/shadok-sync/dev/app/
shadok publish --session "$NAMESPACE/quarkus-live" \
  --url "$SYNC_URL" --ca-file "$SYNC_CA"
```

`clean` removes stale compiler and staged files before rebuilding. Only a successful build reaches publication. This updates classes/resources; it does not regenerate the mounted mutable package. Changes to dependencies, extensions or build-time configuration are outside this classes-only update. They require the project's normal artifact delivery process.

For a private gateway CA, set `SYNC_CA` to its absolute PEM file path; otherwise leave it empty. The workstation/CI runner needs gateway access; its daemon does not need kubeconfig. Do not run concurrent builds into the same output directory.

This route uses Shadok for transport. Do not simultaneously start Quarkus's separate HTTP `remote-dev` synchronization client against the same application.

## 7. Activate and prove reload

```sh
kubectl --context "$CONTEXT" apply -f live/session.yaml
kubectl --context "$CONTEXT" -n "$NAMESPACE" patch developmentsession quarkus-live \
  --type merge -p '{"spec":{"enabled":true}}'
kubectl --context "$CONTEXT" -n "$NAMESPACE" get developmentsession quarkus-live -o yaml
```

Wait for `Ready=True` for the current generation and the application endpoint to respond. Platform logs must show `Live Coding activated`. The application container image digest must match the production baseline. Before the first publication, compare the application JAR checksum in the live directory with the original image's application JAR: they must be identical.

Run the build/publish command in chapter 6. Then perform each check:

| Change in your application | Expected HTTP result after build and publication |
| --- | --- |
| Add an endpoint method to an existing REST resource | Previously absent route: 404 → 200 |
| Add a new REST resource class | New route: 404 → 200 |
| Remove that method and class, then clean-build | Both routes: 200 → 404; unchanged route still responds |

Issue actual requests: Quarkus checks changes through its live request handling. An ACK only proves file delivery. With pod read permissions, save this output before and after the changes, using the application's actual selector:

```sh
kubectl --context "$CONTEXT" -n "$NAMESPACE" get pods -l app=YOUR_APP_LABEL \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.uid}{" "}{range .status.containerStatuses[*]}{.name}{" "}{.containerID}{" "}{.restartCount}{"\n"}{end}{end}'
curl -i "$APP_URL/YOUR_NEW_ENDPOINT"
```

Pod UID, application container ID and restart count must remain unchanged. Platform logs should show Quarkus restarting its application for changed classes. A framework restart can briefly interrupt requests; it is not a Kubernetes container restart. If you only have session rights, have the platform collect this proof.

## 8. Return to production

Run from the same project directory as publication/watch, with the same `SYNC_URL` and `SYNC_CA`. These values identify the local synchronization job.

```sh
shadok unwatch --session "$NAMESPACE/quarkus-live" \
  --url "$SYNC_URL" --ca-file "$SYNC_CA"
kubectl --context "$CONTEXT" -n "$NAMESPACE" patch developmentsession quarkus-live \
  --type merge -p '{"spec":{"enabled":false}}'
kubectl --context "$CONTEXT" -n "$NAMESPACE" get developmentsession quarkus-live -o yaml
curl -i "$APP_URL/YOUR_EXISTING_ENDPOINT"
```

Check `Ready=True`, reason `Baseline`, for the current generation. The platform verifies the original command, image and Deployment configuration. The live emptyDirs are removed with the live pods.

References: [Quarkus Maven remote development](https://quarkus.io/guides/maven-tooling/#remote-development-mode), [Quarkus Gradle remote development](https://quarkus.io/guides/gradle-tooling/#remote-development-mode).
