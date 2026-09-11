# Spring DevTools from a volume: live proof

Executed on 2026-09-11 in the isolated Kind cluster `shadok-go-e2e`, Kubernetes 1.36.1, Spring Boot 3.5.6, Java 21. The application image is `shadok-spring:local` in both production and live mode. Its `/app/lib` does not contain DevTools.

The platform populated PVC `spring-devtools` with the matching Maven-resolved DevTools JAR using a temporary loader pod, then deleted that loader. The application Deployment mounts the PVC read-only at `/opt/devtools`. Its normal Java command excludes that path. The DevelopmentSession has no image override and adds `/opt/devtools/*` to the live classpath. Existing Shadok behavior preserves the mount; no new operator code or CRD fields are required.

The test checks identical application image digests before and after activation. It then compiles on the host, publishes through the daemon and HTTPS gateway, and checks real HTTP routes:

```text
PASS Spring production baseline: no DevTools in application libraries; external JAR mounted but not loaded
PASS Spring live activation: same production image digest, DevTools from read-only PVC
PASS Spring DevTools: added controller method 404 -> 200; same Pod and container
PASS Spring DevTools: new @RestController route 404 -> 200 after build/sync; same Pod UID, container ID and restart count; DevTools restart logged
PASS Spring DevTools: deleted controller .class absent in Pod, route 200 -> 404; remaining method still responds; same Pod and container
PASS spring: Helm instance, HTTPS route, inactive/missing/isolation, live response, replacement, exact baseline restoration
PASS post-test inspection: original production command restored; no restartedMain in production logs
```

New method and controller routes changed from 404 to 200. After deleting the controller and publishing a clean build, its `.class` was absent in the pod and its route returned 404, while the other method remained accessible. Across these edits the test compared Pod UID, container ID and restart count. DevTools restarts the application context inside the JVM. A later deliberate pod replacement separately verifies snapshot recovery.

## Reproduce

See the [Spring guide](../operator-go/internal/guidance/topics/spring.md) and runnable [sample manifests](../pods/spring-hello/kubernetes/production.yaml). Build/load the production image, prepare the test cluster with Shadok infrastructure, and run `python3 operator-go/test/e2e/kind_e2e.py --stack spring` from the repository root with JDK 17+ and Maven available. Run `mvn verify` in the sample first to resolve the matching DevTools JAR.

## Scope

The PVC and mount are configured by the platform before activation, not attached on demand by the operator. The daemon does not bootstrap DevTools. Production can see the mounted JAR but does not load it. The volume remains after session shutdown because it belongs to the platform. The test's ReadWriteOnce PVC is a single-node Kind example, not a multi-node storage guarantee. The unchanged image must already supply Java and compatible application dependencies. This sample uses unpacked classes and libraries; it does not demonstrate extraction of arbitrary executable JAR layouts. No public release was created by this test.
