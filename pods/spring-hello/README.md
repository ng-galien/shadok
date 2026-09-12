# Spring Boot 4 sample

Requirements: JDK 17+, Maven, Docker and an installed Shadok operator. Run from this directory:

```sh
mvn clean verify
docker build -t shadok-spring:local .
```

Follow the [Spring setup guide](../../operator-go/internal/guidance/topics/spring.md) to prepare the DevTools volume, deploy the application and activate the session.

The production image uses Spring Boot layers and runs `java -jar /app/application.jar`. Live mode keeps that image and loads DevTools from a read-only volume.

After configuring a destination:

```sh
shadok build --config shadok.yaml --group service -- mvn verify
# After deleting or renaming a source file:
shadok build --config shadok.yaml --group service -- mvn clean verify
```

Check the changed endpoint over HTTP. For the integration test, follow [Spring reload validation](../../docs/SPRING_LAYERED_IMAGE_VALIDATION.md).
