# Spring Boot 4 sample

Requirements: JDK 17+, Maven, Docker and an installed Shadok operator. Run from this directory:

```sh
mvn clean verify
docker build -t shadok-spring:local .
```

Follow the [Spring setup guide](../../operator-go/internal/guidance/topics/spring.md) to configure the session. The operator provisions and mounts DevTools automatically; the production Deployment needs no tools patch.

The production image uses Spring Boot layers and runs `java -jar /app/application.jar`. Live mode keeps that image and loads DevTools from a read-only volume.

Set `SHADOK_URL` to the gateway origin and `NAMESPACE` to the application namespace. Then run:

```sh
shadok build --session "$NAMESPACE/spring-live" -- mvn verify
# After deleting or renaming a source file:
shadok build --session "$NAMESPACE/spring-live" -- mvn clean verify
```

Check the changed endpoint over HTTP. For the integration test, follow [Spring reload validation](../../docs/SPRING_LAYERED_IMAGE_VALIDATION.md).
