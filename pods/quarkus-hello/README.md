# Quarkus build fixture

## Build the production JVM package

Run from this directory with JDK 17+:

```sh
./gradlew quarkusBuild -Dquarkus.container-image.build=false -Dquarkus.package.jar.type=fast-jar
docker build -f src/main/docker/Dockerfile.jvm -t shadok-quarkus:local .
```

This is a normal fast-jar image. It does not contain Quarkus's remote-dev deployment libraries/model. Live mode supplies only the matching framework resources through a read-only volume; application code remains sourced from this image.

## Local development

```sh
./gradlew quarkusDev
```

## Build-output staging

`stageShadok` uses Gradle's standard `Sync` task to stage compiled application classes/resources at `build/shadok-sync/dev/app`. `shadokPublish` depends on that task and invokes `shadok publish` for the configured destination. The complete live test also provisions the framework resources required by remote dev.

For operating on another project's existing image, use the complete [Quarkus guide](../../operator-go/internal/guidance/topics/quarkus.md), including framework resource preparation and all YAML files. See [the live validation procedure](../../docs/QUARKUS_LIVE_VALIDATION.md) for this fixture.
