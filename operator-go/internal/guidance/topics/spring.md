# Put an existing Spring Boot JVM application into live mode

Work in the application's repository. Keep its production image and its existing Helm/Deployment configuration. The session declares DevTools as a verified tool file. The operator downloads it into a per-pod volume and mounts it read-only before Java starts. At each new pod startup, a standard JDK init container extracts the JAR copied from the production image into Shadok working volumes. It requires no Shadok Maven profile.

Create these files in the application repository:

| File | Purpose |
| --- | --- |
| `live/session.yaml` | Select the application, writable directory and live command |

## 1. Identify the actual image layout

Obtain the rendered Deployment and immutable image reference from the platform. If you can read the Deployment:

```sh
export CONTEXT=YOUR_CONTEXT
export NAMESPACE=YOUR_APPLICATION_NAMESPACE
export DEPLOYMENT=YOUR_EXISTING_DEPLOYMENT
export APP_URL=https://YOUR_APPLICATION_HOST
export SYNC_CA="" # Set an absolute PEM CA path only for a private gateway CA.
kubectl --context "$CONTEXT" -n "$NAMESPACE" get deployment "$DEPLOYMENT" -o yaml
```

Record the application container name, image, UID/GID, working directory, environment, JVM options, port and probes. Inspect the image without starting the application:

```sh
export IMAGE=YOUR_PRODUCTION_IMAGE_REFERENCE
export APP_JAR=/actual/path/in/image/application.jar
docker pull "$IMAGE"
docker image inspect "$IMAGE"
mkdir -p live/inspect
CONTAINER_ID=$(docker create "$IMAGE")
docker cp "$CONTAINER_ID:$APP_JAR" live/inspect/application.jar
docker rm "$CONTAINER_ID"
jar tf live/inspect/application.jar
unzip -p live/inspect/application.jar META-INF/MANIFEST.MF
```

Use the result to select the layout:

| What the image contains | Main class and dependencies for live startup |
| --- | --- |
| Spring's efficient layered layout: a regular application JAR plus external `lib/` | Actual application `Main-Class`; retain the image's external library directory |
| Executable Boot JAR with `BOOT-INF/classes/` and `BOOT-INF/lib/` | Application `Start-Class`, not `JarLauncher`; extract the nested libraries too |
| Already extracted application directory | Seed that directory directly; an archive extractor is unnecessary |
| Native executable | This JVM/DevTools procedure does not apply; obtain a JVM artifact and compatible runtime from the project |

Layer names in a Dockerfile do not establish runtime paths. Inspect the built image. Do not run `jarmode=tools` against an unknown regular JAR to discover its layout: it can launch the application.

Resolve the exact Spring Boot version from the project's effective dependencies and confirm it matches the image. Record the application's main class, not a Spring Boot launcher. For the configurations below, replace:

- `APPLICATION_NAMESPACE`, `EXISTING_DEPLOYMENT`, `APPLICATION_CONTAINER`.
- `1000` with the real non-root runtime UID/GID; use a compatible `fsGroup` for storage.
- `/app/application.jar`, `/app/lib` and `com.company.Application` with inspected values.

The application image needs its normal Java runtime. The initialization image provides `sh`, `jar` and `cp`; it writes to the shared live volumes. Retain the application's port, external configuration and required JVM options. Select an approved JDK initialization image compatible with the cluster architecture, such as `eclipse-temurin:21-jdk`; the application image is not replaced.

The initialization YAML uses `/live/packaged/application.jar`. If the real image contains `/srv/orders/orders-service.jar`, set `packaged.imagePath` to `/srv/orders` and the init command's archive path to `/live/packaged/orders-service.jar`. The local inspection filename does not rename the archive inside the image.

## 2. Configure DevTools

Determine the Spring Boot version used by the production image. Set the DevTools URL to that exact version in Maven Central or your approved HTTPS artifact repository, and record its SHA256 from the trusted build/repository. The example below uses Spring Boot 4.1.1; change both URL and checksum for another version.

No PVC, upload pod or Deployment patch is needed. The operator creates the tool volume, downloads and verifies the JAR, then mounts it at `/opt/spring-live-tools`. A failed download or checksum stops initialization; Java does not start with incomplete tools. Each replacement pod repeats this preparation, so the artifact URL must be reachable from the cluster.

If the platform already provides a populated PVC, replace the `files` source below with `persistentVolumeClaim: {claimName: YOUR_CLAIM, readOnly: true}`. The operator manages its mount; the PVC remains platform-owned.

## 3. Create the live session

Create `live/session.yaml`, replacing the recorded application values:

```yaml
apiVersion: shadok.org/v1alpha1
kind: DevelopmentSession
metadata:
  name: spring-live
  namespace: APPLICATION_NAMESPACE
spec:
  enabled: false
  deployment: EXISTING_DEPLOYMENT
  container: APPLICATION_CONTAINER
  runAsUser: 1000
  runAsGroup: 1000
  directories:
    - name: packaged
      imagePath: /app
      mountPath: /live/packaged
    - name: classes
      mountPath: /live/classes
      localPath: target/classes
  volumes:
    - name: devtools
      mountPath: /opt/spring-live-tools
      readOnly: true
      files:
        - path: devtools.jar
          url: https://repo.maven.apache.org/maven2/org/springframework/boot/spring-boot-devtools/4.1.1/spring-boot-devtools-4.1.1.jar
          sha256: 5aa3b3f253248d38e8785651b0bb33c5b71032612780456c62841ce0f034cc58
  init:
    - name: unpack
      image: eclipse-temurin:21-jdk
      command: [sh]
      args:
        - -ec
        - |
          mkdir -p /live/packaged/unpacked
          cd /live/packaged/unpacked
          jar --extract --file /live/packaged/application.jar
          if [ -d BOOT-INF/classes ]; then
            cp -R BOOT-INF/classes/. /live/classes/
          else
            cp -R . /live/classes/
          fi
  start:
    command: [java]
    args:
      - -cp
      - /live/classes:/live/resources:/live/packaged/unpacked/BOOT-INF/lib/*:/app/lib/*:/opt/spring-live-tools/devtools.jar
      - com.company.Application
    workingDir: /app
```

Startup order is explicit:

1. Shadok copies `/app` from the production image into the `packaged` emptyDir; the application image's `/app` is not masked.
2. Shadok downloads the declared DevTools file, checks its SHA256 and makes it available in the read-only tool mount.
3. The JDK init container extracts `application.jar` into that emptyDir and copies its application files into `classes`.
4. Kubernetes starts the application only after successful extraction. The application uses its original image's Java, the extracted classes and mounted DevTools.

For a regular layered JAR, `/app/lib/*` supplies the original image's libraries. For a Boot executable JAR, `/live/packaged/unpacked/BOOT-INF/lib/*` supplies its extracted libraries. Preserve required JVM arguments in `start.args`, before the application main class. Do not retain `-jar` or a production AOT cache option tied to a different classpath.

For an already extracted application directory, seed `classes` from that directory and omit the `packaged` directory and `init` step. No external volume contains application JARs/classes in either case. The packaged working directory is not a synchronized root; only application classes/resources are mirrored.

## 4. Build output paths

`directories[].localPath` is relative to the directory where you run the CLI. The session above publishes Maven's `target/classes`. Shadok reads this mapping from the session through the gateway; no local configuration file or group is required. The `packaged` directory has no `localPath`, so it is never synchronized.

For Gradle, replace the `classes` entry and add resources when the project has them:

```yaml
  directories:
    - name: packaged
      imagePath: /app
      mountPath: /live/packaged
    - name: classes
      mountPath: /live/classes
      localPath: build/classes/java/main
    - name: resources
      mountPath: /live/resources
      localPath: build/resources/main
```

Include the corresponding Kotlin/module outputs when applicable. Build outputs must remain inside the project working directory. Dependencies remain outside the mirror.

## 5. Activate, build and synchronize

Use the gateway origin supplied by the platform. The namespace and session name identify the synchronization target; the gateway URL is not the application's HTTP URL:

```sh
export SYNC_URL=https://YOUR_SYNC_HOST
kubectl --context "$CONTEXT" apply -f live/session.yaml
kubectl --context "$CONTEXT" -n "$NAMESPACE" patch developmentsession spring-live \
  --type merge -p '{"spec":{"enabled":true}}'
kubectl --context "$CONTEXT" -n "$NAMESPACE" get developmentsession spring-live -o yaml
```

Wait for `Ready=True` for the current generation and confirm the application responds. If you cannot read pods, ask the platform for the startup logs when this fails.

Run from the application module:

```sh
shadok build --session "$NAMESPACE/spring-live" \
  --url "$SYNC_URL" --ca-file "$SYNC_CA" \
  -- mvn clean verify
```

Gradle equivalent:

```sh
shadok build --session "$NAMESPACE/spring-live" \
  --url "$SYNC_URL" --ca-file "$SYNC_CA" \
  -- ./gradlew clean build
```

Shadok executes the command after `--`. Only when that command succeeds does it snapshot the configured directories and send the changed files and deletions. There is no publishing profile, custom Java helper or additional staging script. A CI job uses exactly the same command. For a private gateway CA, set `SYNC_CA` to its absolute PEM file path; otherwise leave it empty.

Do not run concurrent builds against the same output directories. Clean builds remove obsolete `.class` files after source deletions; Shadok mirrors those deletions.

Add an endpoint method, build and publish, then call it. Add a controller class, repeat, then delete it and repeat: expect 404 → 200 → 404. DevTools reloads the application in the same container; it does not guarantee uninterrupted requests. Check Pod UID, application container ID and restart count remain unchanged across these updates. For an agent with pod read access, capture this before the first update and after each update (replace the selector with the Deployment's actual selector):

```sh
kubectl --context "$CONTEXT" -n "$NAMESPACE" get pods -l app=YOUR_APP_LABEL \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.uid}{" "}{range .status.containerStatuses[*]}{.name}{" "}{.containerID}{" "}{.restartCount}{"\n"}{end}{end}'
curl -i "$APP_URL/YOUR_NEW_ENDPOINT"
```

If your permissions cover only sessions, have the platform collect the identity comparison and startup/reload logs. Do not claim a no-restart proof from the HTTP result alone.

When dependencies or the Boot version change, prepare matching runtime libraries/tools before starting a new session. Publishing application classes does not update the separate library directories.

## 6. Restore production

Run from the same project directory as publication/watch, with the same `SYNC_URL` and `SYNC_CA`. These values identify the local synchronization job.

```sh
shadok unwatch --session "$NAMESPACE/spring-live" \
  --url "$SYNC_URL" --ca-file "$SYNC_CA"
kubectl --context "$CONTEXT" -n "$NAMESPACE" patch developmentsession spring-live \
  --type merge -p '{"spec":{"enabled":false}}'
kubectl --context "$CONTEXT" -n "$NAMESPACE" get developmentsession spring-live -o yaml
```

Check `Ready=True`, reason `Baseline`, for the current generation and call the original endpoint. The platform can verify the original startup command and image are restored. The operator removes the live tool mount, working volumes and initialization containers. The original Deployment needs no preinstalled tooling.

References: [Spring Boot container images](https://docs.spring.io/spring-boot/reference/packaging/container-images/dockerfiles.html), [DevTools](https://docs.spring.io/spring-boot/reference/using/devtools.html).
