# Spring Boot live development

## Production to live, and back

Read the [complete Spring walkthrough](../../operator-go/internal/guidance/topics/spring.md), also embedded as `shadok learn spring` / `shadok docs spring` in the next rebuilt CLI. It includes a complete DevelopmentSession YAML, destination setup, activation, build commands and restoration. The already published 1.0.0 binary does not yet contain this topic.

The switch is explicit: the platform Deployment starts on the production image; the session's `spec.image` selects the compatible image with DevTools. Shadok saves the original PodTemplate and rolls out the live image with a classes volume seeded **from that live image**. Later builds update the volume; DevTools restarts Spring inside the same container. Disabling the session restores the production template through a rollout. Shadok does not inject DevTools into an arbitrary production JAR.

See [live validation evidence](../../docs/SPRING_LIVE_VALIDATION.md) for the verified additions/deletions and return to production.

## Run locally

From `pods/spring-hello`, with JDK 17+ and Maven.

```sh
mvn verify
java -cp "target/classes:target/lib/*" example.Application
```

Open http://localhost:8080/hello. Stop the server with Ctrl+C.

## Run with Shadok

Follow the [shared session and destination setup](../README.md#before-synchronizing-an-example). The commands below also run from this example directory.

Build the classes and two image targets:

```sh
mvn verify
docker build --target production -t shadok-spring:local .
docker build --target live -t shadok-spring-live:local .
```

The default `production` target contains classes and runtime dependencies, with the DevTools JAR removed. The `live` target includes DevTools. Maven runs on the build machine, not in either pod. Publish the two images to your registry for a remote cluster; for the local test cluster, load both with `kind load docker-image shadok-spring:local shadok-spring-live:local --name shadok-go-e2e`.

The existing Deployment must use an image with that layout. Configure a DevelopmentSession with `image: shadok-spring-live:local` (or its registry reference), container `app`, directory name `classes`, imagePath and mountPath `/app/classes`, UID/GID 1000, workingDir `/app`, and command `java` with args `[-cp, "/app/classes:/app/lib/*", example.Application]`.

After activating the session and configuring the gateway destination, run from this directory:

```sh
mvn -Pshadok verify
```

The profile publishes `target/classes` only after a successful build. Alternatively use `shadok build --config shadok.yaml --group service -- mvn verify` without the profile. DevTools must remain on the classpath and enabled; dependency changes require rebuilding a compatible live image. Verify `/hello` after changing the response. File acknowledgement and application restart are separate checks.

See [release installation](../../docs/INSTALL_RELEASE.md), [session configuration](../../operator-go/internal/guidance/topics/configure.md) and [build hooks](../../operator-go/internal/guidance/topics/builds.md). The platform provides the Deployment; Shadok does not create its application dependencies.

## Class additions and removals

DevTools restarts the Spring application context when compiled classes change. Adding a controller or a mapped method can register new routes without restarting the pod/container. This is an application restart inside the JVM, not JVM hot-swap.

Shadok mirrors the configured compiled output directory: new `.class` files are uploaded and absent files are removed, respecting exclusions. Deleting a Java source file alone may leave its old `.class` in Maven output. After deletions or renames, use `mvn -Pshadok clean verify` (or `shadok build --config shadok.yaml --group service -- mvn clean verify`) to publish a clean output snapshot. Do not watch a partially rebuilt `target/classes` directory directly.

The live integration scenario is `python3 operator-go/test/e2e/kind_e2e.py --stack spring`, run from the repository root against the prepared `shadok-go-e2e` cluster with the operator/gateway/tools and both Spring images loaded. It checks the production baseline without DevTools, activation with the live image, adding a mapped method, adding/removing a controller, HTTP responses and stable pod/container identity, then baseline restoration.
