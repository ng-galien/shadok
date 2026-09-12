# Write the target project's Shadok configuration

Complete `shadok learn inspect` and the runtime guide first. Replace every uppercase placeholder below with an inspected value.

## 1. Create the session manifest

```yaml
apiVersion: shadok.org/v1alpha1
kind: DevelopmentSession
metadata:
  name: SESSION_NAME
  namespace: APPLICATION_NAMESPACE
spec:
  enabled: false
  deployment: EXISTING_DEPLOYMENT
  container: EXISTING_CONTAINER
  runAsUser: 1000
  runAsGroup: 1000
  directories:
    - name: application
      imagePath: /VERIFIED/IMAGE/DIRECTORY
      mountPath: /LIVE/DIRECTORY
  start:
    command: [EXECUTABLE]
    args: [ARGUMENT_1, ARGUMENT_2]
    workingDir: /VERIFIED/WORKING/DIRECTORY
```

Save as `session.yaml` in the target project or add these values through its existing chart. Replace UID/GID as well as paths. Keep `spec.image` absent to retain the production image.

| Field | What the agent must configure |
| --- | --- |
| `deployment`, `container` | Existing workload and application container |
| `directories[].name` | Logical name reused by `roots[].mount` in the local config |
| `imagePath` | Existing directory copied from the image to initialize the volume |
| `mountPath` | Directory mounted in the application for synchronized files |
| `start.command/args` | Exact executable and arguments established by the runtime guide |
| `workingDir` | Directory needed for relative imports, classpath or application paths |

**`imagePath` copies a directory; it does not extract JARs, install dependencies or infer frameworks.** For archives, configure `spec.init` with a standard tooling image and extraction command as shown in the complete Spring guide. A mount seeded from a verified empty image directory must be populated before the application starts.

Volume/tool provisioning belongs in the existing platform Deployment. `spec.init` runs ordered initialization containers after seeding and mounts the declared live directories. It does not import application artifacts from another image or invent a framework configuration. Extra platform tool volumes remain declared in the existing Deployment. `spec.image`, when explicitly selected, changes both application and seed image.

## 2. Map local files

Create `shadok.yaml` in the application repository:

```yaml
version: 1
project: PROJECT_NAME
groups:
  service:
    mode: build
    roots:
      - mount: application
        path: ACTUAL_BUILD_OUTPUT_DIRECTORY
```

Use paths relative to this file. Use `mode: watch` only for source trees that can be consumed directly by the live process. Each root mirrors its directory, including deletions; do not include dependencies or files owned by the image in that root.

## 3. Select the destination

Follow `shadok learn network`. The destination names the gateway origin, application namespace and Deployment, not the session name.

## 4. Apply and activate

```sh
kubectl --context "$CONTEXT" apply -f session.yaml
kubectl --context "$CONTEXT" -n "$NAMESPACE" patch developmentsession "$SESSION" \
  --type merge -p '{"spec":{"enabled":true}}'
kubectl --context "$CONTEXT" -n "$NAMESPACE" get developmentsession "$SESSION" -o yaml
```

Verify Ready=True for the current observed generation, then check application readiness and its URL. Do not publish into a session whose bootstrap/startup has failed.

Run the configured build/watch command from `shadok learn builds`, then perform `shadok learn verify`.
