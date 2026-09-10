# Spring production-to-live validation

Executed on 2026-09-10 against the isolated `shadok-go-e2e` Kind cluster, Kubernetes 1.36.1, Spring Boot 3.5.6 and Java 21. This was a real HTTP/build/synchronization test, not a unit test.

## Setup

The sample Dockerfile now has two targets. `production` (the default) removes the DevTools JAR; `live` includes it. Both use the same compiled baseline application and runtime libraries. The platform Deployment starts on `shadok-spring:local`; the DevelopmentSession selects `shadok-spring-live:local`. The operator does not install DevTools into an arbitrary production image: it uses the explicitly configured live image.

The test asserts that DevTools is absent from the production container and that baseline logs do not show `restartedMain`. After activation, Maven compiles on the host and Shadok publishes compiled classes through its HTTPS gateway. DevTools restarts the Spring application context inside the existing JVM.

## Observed results

```text
PASS Spring production baseline: DevTools jar absent; normal application startup
PASS Spring DevTools: added controller method 404 -> 200; same Pod and container
PASS Spring DevTools: new @RestController route 404 -> 200 after build/sync; same Pod UID, container ID and restart count; DevTools restart logged
PASS Spring DevTools: deleted controller .class absent in Pod, route 200 -> 404; remaining method still responds; same Pod and container
PASS spring: Helm instance, HTTPS route, inactive/missing/isolation, live response, replacement, exact baseline restoration
PASS post-test inspection: production image restored, DevTools JAR absent
```

For both additions, the new URL initially returns 404, then returns 200 with the expected body. The test compares Pod UID, application container ID and restart count across each change. For deletion, it checks the class file is absent in the live pod, the removed route returns 404, and the retained method still returns 200. The later intentional pod deletion tests synchronization recovery separately; it is not used to make the new routes appear.

DevTools log evidence captured during the live phase:

```text

```

## Reproduce and limits

See the [Spring sample guide](../pods/spring-hello/README.md) for both image builds and the live test command. The scenario is implemented in [kind_e2e.py](../operator-go/test/e2e/kind_e2e.py).

A clean Maven build is used after deleting the Java controller so stale compiled classes cannot remain in `target/classes`. Shadok synchronizes compiled files, not Java source semantics. Dependency changes still require an updated live image. DevTools causes an application-context restart with a short interruption; this is not zero-downtime JVM hot-swap. The test uses the current replacement mode, not the proposed parallel A/B mode.

The first attempt at the strengthened scenario exposed a test port-forward connection closing during a Spring restart. The HTTP checks now reconnect before retrying; the full rerun above passed. An earlier run was stopped because its baseline still included DevTools.
