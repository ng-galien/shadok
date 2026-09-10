# Quarkus application example

This application demonstrates REST endpoints, Kubernetes deployment configuration and a Gradle hook for publishing completed class/resource outputs.

Run from this example directory (`pods/quarkus-hello`), with JDK 17 or newer:

```sh
./gradlew quarkusDev
./gradlew test
./gradlew build
```

The REST endpoints are `/hello` and `/hello/json`; health is exposed through `/q/health`. Application and image configuration is in `src/main/resources/application.properties`. Inspect build/image settings before invoking a task configured to build or push containers.

The optional `shadokPublish` task depends on classes and tests, then invokes `shadok publish --config shadok.yaml --group quarkus-outputs`. Install the CLI on PATH and configure the personal destination first. Use `shadok learn` for the complete build and synchronization workflow.

A successful Gradle hook demonstrates output publication, not remote Quarkus dev mode. The selected application image and start command must supply a compatible reload mechanism; Shadok does not infer one from the language.

The Gradle wrapper, version catalog, build settings and `shadok.yaml` belong to this example. The wrapper downloads the pinned, checksum-verified Gradle distribution on first use. `./gradlew spotlessCheck` checks formatting locally. No Gradle installation or root Gradle project is needed by Shadok itself.

Open http://localhost:8080/hello during `./gradlew quarkusDev`; stop with Ctrl+C. For the build hook, follow the [shared session and destination setup](../README.md#before-synchronizing-an-example). Its `classes` and `resources` mounts publish the output roots in this example's `shadok.yaml`.

The supplied JVM Dockerfile packages `build/quarkus-app` as a normal Quarkus application. It does not establish a remote live classpath/restart arrangement for those two mounts. The platform must provide a compatible development image and live command before using the hook for reload; the local Quarkus test and hook dry-run do not validate remote dev mode.
