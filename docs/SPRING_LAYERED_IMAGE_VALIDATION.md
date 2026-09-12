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
| Activate live mode | Same image digest; JDK init extracts the production JAR inside the pod; external volume contains only DevTools |
| Change `/hello` | Updated response after build/sync |
| Add a controller method | Endpoint changes from 404 to 200 |
| Add a controller | New endpoint returns 200 |
| Delete the controller and clean-build | Endpoint returns 404; class file is absent |
| Reload after each edit | Same pod UID, container ID and restart count |
| Replace the pod | Synchronized revision recovered |
| Disable the session | Production configuration restored |

Check HTTP results, not only transfer acknowledgements. DevTools may briefly interrupt requests. Activation and restoration roll out pods; reloads during the session do not.

The Spring Boot 4.1.1 layered-image run passed with the JDK initialization step. The external volume contained only `spring-boot-devtools.jar`; the production application was extracted inside the pod. HTTP additions/deletion, unchanged container identity, replacement recovery and exact Deployment restoration all passed.
