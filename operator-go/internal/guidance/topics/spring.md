# Put an existing Spring Boot JVM application into live mode

Work in the application's repository. Keep its production image and its existing Helm/Deployment configuration. This procedure mounts only DevTools as an external tool. At each new pod startup, a standard JDK init container extracts the JAR copied from the production image into Shadok working volumes. It requires no Shadok Maven profile.

Create these files in the application repository:

| File | Purpose |
| --- | --- |
| `live/tools-volume.yaml` | Platform-owned DevTools storage and temporary upload pod |
| `live/deployment-tools.yaml` | Mount the tools in the existing application Deployment |
| `live/session.yaml` | Select the application, writable directory and live command |
| `shadok.yaml` | Map the local compiler output to that directory |

## 1. Identify the actual image layout

Obtain the rendered Deployment and immutable image reference from the platform. If you can read the Deployment:

```sh
export CONTEXT=YOUR_CONTEXT
export NAMESPACE=YOUR_APPLICATION_NAMESPACE
export DEPLOYMENT=YOUR_EXISTING_DEPLOYMENT
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
- `/tmp` with an existing **empty** image directory for seeding the live volume; verify it first.

The application image needs its normal Java runtime. The initialization image provides `sh`, `jar` and `cp`; it writes to the shared live volumes. Retain the application's port, external configuration and required JVM options. Select an approved JDK initialization image compatible with the cluster architecture, such as `eclipse-temurin:21-jdk`; the application image is not replaced.

The initialization YAML uses `/live/packaged/application.jar`. If the real image contains `/srv/orders/orders-service.jar`, set `packaged.imagePath` to `/srv/orders` and the init command's archive path to `/live/packaged/orders-service.jar`. The local inspection filename does not rename the archive inside the image.

## 2. Prepare the tools on the build machine

Set `BOOT_VERSION` to the version established above. Download only the matching DevTools JAR; do not add it to the production artifact:

```sh
export BOOT_VERSION=YOUR_EXACT_BOOT_VERSION
mkdir -p live/tools
mvn org.apache.maven.plugins:maven-dependency-plugin:3.8.1:copy \
  -Dartifact=org.springframework.boot:spring-boot-devtools:"$BOOT_VERSION" \
  -DoutputDirectory="$PWD/live/tools"
```

Do not extract or rebuild the application on this machine. The only file uploaded is the matching DevTools JAR. Application files will be taken from the production image inside the pod in chapter 4.

## 3. Provision and mount the tools — platform operation

An agent with only DevelopmentSession permissions supplies these files to the platform team; it does not need permission to create arbitrary workloads. Incorporate the mount into the application's existing chart so the platform's next deployment retains it.

Create `live/tools-volume.yaml`. Replace the namespace, IDs, storage class if required, and `APPROVED_IMAGE_WITH_SH_AND_TAR` with an approved image containing `sh` and `tar`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: spring-live-tools
  namespace: APPLICATION_NAMESPACE
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 32Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: spring-live-tools-loader
  namespace: APPLICATION_NAMESPACE
spec:
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
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
        claimName: spring-live-tools
```

Choose storage that supports the application's replica placement; `ReadWriteOnce` requires the same node for concurrent mounts. Populate it before live activation:

```sh
kubectl --context "$CONTEXT" apply -f live/tools-volume.yaml
kubectl --context "$CONTEXT" -n "$NAMESPACE" wait \
  --for=condition=Ready pod/spring-live-tools-loader --timeout=120s
kubectl --context "$CONTEXT" -n "$NAMESPACE" cp \
  "live/tools/spring-boot-devtools-$BOOT_VERSION.jar" spring-live-tools-loader:/tools/devtools.jar
kubectl --context "$CONTEXT" -n "$NAMESPACE" delete pod spring-live-tools-loader
```

Create `live/deployment-tools.yaml` as a **strategic merge patch**, not a replacement Deployment:

```yaml
spec:
  template:
    spec:
      securityContext:
        fsGroup: 1000
      volumes:
        - name: spring-live-tools
          persistentVolumeClaim:
            claimName: spring-live-tools
            readOnly: true
      containers:
        - name: APPLICATION_CONTAINER
          volumeMounts:
            - name: spring-live-tools
              mountPath: /opt/spring-live-tools
              readOnly: true
```

Merge this fragment through the existing chart. For a direct platform-managed installation:

```sh
kubectl --context "$CONTEXT" -n "$NAMESPACE" patch deployment "$DEPLOYMENT" \
  --type strategic --patch-file live/deployment-tools.yaml
kubectl --context "$CONTEXT" -n "$NAMESPACE" rollout status deployment/"$DEPLOYMENT"
```

Check the normal application endpoint. Its image and production command have not changed; the mounted tools are not on its production classpath.

## 4. Create the live session

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
      imagePath: /tmp
      mountPath: /live/classes
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
2. The JDK init container extracts `application.jar` into that emptyDir and copies its application files into `classes`.
3. Kubernetes starts the application only after successful extraction. The application uses its original image's Java, the extracted classes and mounted DevTools.

For a regular layered JAR, `/app/lib/*` supplies the original image's libraries. For a Boot executable JAR, `/live/packaged/unpacked/BOOT-INF/lib/*` supplies its extracted libraries. Preserve required JVM arguments in `start.args`, before the application main class. Do not retain `-jar` or a production AOT cache option tied to a different classpath.

For an already extracted application directory, seed `classes` from that directory and omit the `packaged` directory and `init` step. No external volume contains application JARs/classes in either case. The packaged working directory is not a synchronized root; only application classes/resources are mirrored.

## 5. Configure the local mirror

Create `shadok.yaml` for Maven. Use the actual application module's output directory:

```yaml
version: 1
project: YOUR_PROJECT
groups:
  service:
    mode: build
    roots:
      - mount: classes
        path: target/classes
```

Maven places classes and resources together in `target/classes`. Libraries remain outside this mirrored directory.

For Gradle, keep the `packaged` directory and `init` step. Use these `directories` in `live/session.yaml`:

```yaml
directories:
  - name: packaged
    imagePath: /app
    mountPath: /live/packaged
  - name: classes
    imagePath: /tmp
    mountPath: /live/classes
  - name: resources
    imagePath: /tmp
    mountPath: /live/resources
```

Use this complete `shadok.yaml` instead:

```yaml
version: 1
project: YOUR_PROJECT
groups:
  service:
    mode: build
    roots:
      - mount: classes
        path: build/classes/java/main
      - mount: resources
        path: build/resources/main
```

These paths are relative to `shadok.yaml`. Verify they exist after the build. If the project has no resources, omit that root and its session directory. The live classpath above includes both directories. Add Kotlin or additional module outputs explicitly when the project uses them; a module left as a dependency JAR does not become reloadable through the main module's mapping.

## 6. Activate, build and synchronize

Use the gateway origin supplied by the platform. The namespace and Deployment identify the target; the gateway URL is not the application's HTTP URL:

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
shadok build --config shadok.yaml --group service \
  --url "$SYNC_URL" --namespace "$NAMESPACE" --deployment "$DEPLOYMENT" \
  -- mvn clean verify
```

Gradle equivalent:

```sh
shadok build --config shadok.yaml --group service \
  --url "$SYNC_URL" --namespace "$NAMESPACE" --deployment "$DEPLOYMENT" \
  -- ./gradlew clean build
```

Shadok executes the command after `--`. Only when that command succeeds does it snapshot the configured directories and send the changed files and deletions. There is no publishing profile, custom Java helper or additional staging script. A CI job uses exactly the same command. For a private CA, add `--ca-file /path/to/company-ca.pem` before `--`.

Do not run concurrent builds against the same output directories. Clean builds remove obsolete `.class` files after source deletions; Shadok mirrors those deletions.

Add an endpoint method, build and publish, then call it. Add a controller class, repeat, then delete it and repeat: expect 404 → 200 → 404. DevTools reloads the application in the same container; it does not guarantee uninterrupted requests. Check Pod UID, application container ID and restart count remain unchanged across these updates. For an agent with pod read access, capture this before the first update and after each update (replace the selector with the Deployment's actual selector):

```sh
kubectl --context "$CONTEXT" -n "$NAMESPACE" get pods -l app=YOUR_APP_LABEL \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.uid}{" "}{range .status.containerStatuses[*]}{.name}{" "}{.containerID}{" "}{.restartCount}{"\n"}{end}{end}'
curl -i "$APP_URL/YOUR_NEW_ENDPOINT"
```

Set `APP_URL` to the application's existing URL. If your permissions cover only sessions, have the platform collect the identity comparison and startup/reload logs. Do not claim a no-restart proof from the HTTP result alone.

When dependencies or the Boot version change, prepare matching runtime libraries/tools before starting a new session. Publishing application classes does not update the separate library directories.

## 7. Restore production

```sh
shadok unwatch --config shadok.yaml --group service \
  --url "$SYNC_URL" --namespace "$NAMESPACE" --deployment "$DEPLOYMENT"
kubectl --context "$CONTEXT" -n "$NAMESPACE" patch developmentsession spring-live \
  --type merge -p '{"spec":{"enabled":false}}'
kubectl --context "$CONTEXT" -n "$NAMESPACE" get developmentsession spring-live -o yaml
```

Check `Ready=True`, reason `Baseline`, for the current generation and call the original endpoint. The platform can verify the original startup command and image are restored. The tool mount stays available but is no longer used by the production command.

References: [Spring Boot container images](https://docs.spring.io/spring-boot/reference/packaging/container-images/dockerfiles.html), [DevTools](https://docs.spring.io/spring-boot/reference/using/devtools.html).
