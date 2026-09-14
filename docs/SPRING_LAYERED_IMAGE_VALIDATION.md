# Test Spring Boot live reload

Prepare the test fixture using [its build instructions](../pods/spring-hello/README.md). Use the dedicated `shadok-go-e2e` Kind cluster, load the production image and set `JAVA_HOME` to a JDK 17+ installation.

From the repository root:

```sh
python3 operator-go/test/e2e/kind_e2e.py --stack spring
```

The test checks:

| Operation | Expected result |
| --- | --- |
| Start production | Layered application JAR, no DevTools loaded |
| Activate live mode | Same image digest; JDK init extracts the production JAR inside the pod; operator downloads/checks DevTools and mounts its per-pod volume; no prior Deployment patch |
| Publish by session name | `--session shadok-live-e2e/spring-live` resolves Deployment `spring`; local output comes from the session; no local sync configuration file or Kubernetes credentials |
| Change `/hello` | Updated response after build/sync |
| Add a controller method | Endpoint changes from 404 to 200 |
| Add a controller | New endpoint returns 200 |
| Delete the controller and clean-build | Endpoint returns 404; class file is absent |
| Reload after each edit | Same pod UID, container ID and restart count |
| Replace the pod | Synchronized revision recovered |
| Disable the session | Production configuration restored |

Check HTTP results, not only transfer acknowledgements. DevTools may briefly interrupt requests. Activation and restoration roll out pods; reloads during the session do not.

Spring Boot 4.1.1 passed with automatic DevTools preparation and the JDK initialization step. The baseline had no DevTools mount. The operator created the tool volume, verified the downloaded JAR and mounted it read-only. HTTP additions/deletion, unchanged container identity, replacement recovery and exact restoration without the tool mount all passed.
