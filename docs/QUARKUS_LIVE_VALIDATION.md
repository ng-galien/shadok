# Test Quarkus production-to-live behavior

## Prepare the dedicated fixture

Use the `shadok-go-e2e` Kind cluster with Shadok's operator/gateway running. Set `JAVA_HOME` to JDK 17+ and install Python 3, Docker, Gradle wrapper prerequisites and kubectl. From `pods/quarkus-hello`:

```sh
./gradlew quarkusBuild -Dquarkus.package.jar.type=fast-jar -Dquarkus.container-image.build=false
docker build -f src/main/docker/Dockerfile.jvm -t shadok-quarkus:local .
kind load docker-image shadok-quarkus:local --name shadok-go-e2e
./gradlew quarkusBuild -Dquarkus.package.jar.type=mutable-jar -Dquarkus.container-image.build=false
```

The image is built **before** generating mutable output. The test copies only `lib/deployment` and `quarkus/build-system.properties` from that output into its framework resource volume. It never uploads the mutable application's JAR, runner or classes.

## Run

From the repository root, with the CLI built at `operator-go/bin/shadok`:

```sh
python3 operator-go/test/e2e/quarkus_live.py
```

Run separately from other gateway tests. It uses namespace `shadok-quarkus-e2e` and restores the application after the run.

## Required observations

| Check | Result verified |
| --- | --- |
| Production startup | Normal fast-jar, prod profile, no live coding |
| Live startup | Same image digest and same application JAR SHA-256 |
| Framework resource volume | Deployment dependencies/model only, no application JAR/classes |
| Add method | Endpoint 404 → 200 |
| Add REST class | Endpoint 404 → 200 |
| Remove method/class and clean-build | Endpoints 200 → 404; removed class absent; baseline endpoint retained |
| Each reload | Identical Pod UID, container ID and restart count |
| Disable session | Exact original Deployment spec and production mode restored |

Quarkus 3.39.3 passed this test with restart count zero. The runtime image digest observed in Kind was `sha256:911f703a504f49693e220cc0af11bd3a058a347cca7d6d4cd36db9af8b3c4d2f`.

For configuring a different application, use the [complete operational guide](../operator-go/internal/guidance/topics/quarkus.md), not this fixture procedure. Match the framework resources to that application's Quarkus build model and dependencies.
