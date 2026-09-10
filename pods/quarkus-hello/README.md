# Quarkus application example

This application demonstrates REST endpoints, Kubernetes deployment configuration and a Gradle hook for publishing completed class/resource outputs.

Run from the repository root:

```sh
./gradlew :pods:quarkus-hello:quarkusDev
./gradlew :pods:quarkus-hello:test
./gradlew :pods:quarkus-hello:build
```

The REST endpoints are `/hello` and `/hello/json`; health is exposed through `/q/health`. Application and image configuration is in `src/main/resources/application.properties`. Inspect build/image settings before invoking a task configured to build or push containers.

The optional `:pods:quarkus-hello:shadokPublish` task depends on classes and tests, then invokes `shadok publish --config shadok.yaml --group quarkus-outputs`. Install the CLI on PATH and configure the personal destination first. Use `shadok learn` for the complete build and synchronization workflow.

A successful Gradle hook demonstrates output publication, not remote Quarkus dev mode. The selected application image and start command must supply a compatible reload mechanism; Shadok does not infer one from the language.
