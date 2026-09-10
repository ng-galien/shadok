# Spring Boot live development

Build the baseline with `mvn verify`, then build the supplied Dockerfile. It includes `target/classes`, runtime dependencies and DevTools; Maven is needed on the build machine, not in the live pod.

The existing Deployment must use an image with that layout. Configure a DevelopmentSession with container `app`, directory name `classes`, imagePath and mountPath `/app/classes`, UID/GID 1000, workingDir `/app`, and command `java` with args `[-cp, "/app/classes:/app/lib/*", example.Application]`.

After activating the session and configuring the gateway destination, run from this directory:

```sh
mvn -Pshadok verify
```

The profile publishes `target/classes` only after a successful build. Alternatively use `shadok build --config shadok.yaml --group service -- mvn verify` without the profile. DevTools must remain on the classpath and enabled; dependency changes require updating the baseline image. Verify `/hello` after changing the response. File acknowledgement and application restart are separate checks.

See [release installation](../../docs/INSTALL_RELEASE.md), [session configuration](../../operator-go/internal/guidance/topics/configure.md) and [build hooks](../../operator-go/internal/guidance/topics/builds.md). The platform provides the Deployment; Shadok does not create its application dependencies.
