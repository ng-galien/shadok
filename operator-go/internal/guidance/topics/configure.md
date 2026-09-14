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
      localPath: ACTUAL_BUILD_OUTPUT_DIRECTORY
  start:
    command: [EXECUTABLE]
    args: [ARGUMENT_1, ARGUMENT_2]
    workingDir: /VERIFIED/WORKING/DIRECTORY
```

Save as `session.yaml` in the target project or add these values through its existing chart. Replace UID/GID as well as paths. Keep `spec.image` absent to retain the production image.

| Field | What the agent must configure |
| --- | --- |
| `deployment`, `container` | Existing workload and application container |
| `directories[].name` | Name of the live directory; the CLI reads it from the session |
| `imagePath` | Existing directory copied from the image to initialize the volume |
| `mountPath` | Directory mounted in the application for synchronized files |
| `localPath` | Corresponding source/build directory relative to the CLI working directory; omit for directories not synchronized |
| `exclude` | Files/directories to keep outside the mirror |
| `start.command/args` | Exact executable and arguments established by the runtime guide |
| `workingDir` | Directory needed for relative imports, classpath or application paths |

**`imagePath` copies a directory; it does not extract JARs, install dependencies or infer frameworks.** For archives, configure `spec.init` with a standard tooling image and extraction command as shown in the complete Spring guide. Omit `imagePath` for an empty working volume.

The operator owns additional mounts declared in `spec.volumes`. `spec.init` runs ordered initialization containers after seeding and tool-file preparation. No preliminary patch of the application Deployment is required.

## 2. Apply and activate

Set the values used in the manifest and select the gateway:

```sh
export CONTEXT=YOUR_CONTEXT
export NAMESPACE=YOUR_APPLICATION_NAMESPACE
export SESSION=YOUR_DEVELOPMENTSESSION_NAME
export SHADOK_URL=https://YOUR_SYNC_GATEWAY
export SYNC_CA="" # Set an absolute PEM CA path only for a private gateway CA.
kubectl --context "$CONTEXT" apply -f session.yaml
kubectl --context "$CONTEXT" -n "$NAMESPACE" patch developmentsession "$SESSION" \
  --type merge -p '{"spec":{"enabled":true}}'
kubectl --context "$CONTEXT" -n "$NAMESPACE" get developmentsession "$SESSION" -o yaml
```

Verify Ready=True for the current observed generation, then check application readiness and its URL. Do not publish into a session whose bootstrap/startup has failed.

## 3. Publish to the session

Run in the application project, after a successful build and any staging required by its runtime guide:

```sh
shadok publish --session "$NAMESPACE/$SESSION" --ca-file "$SYNC_CA"
```

The gateway address identifies the cluster; `--session` identifies the DevelopmentSession resource, not the Deployment. The CLI reads `localPath` and `exclude` from that session and starts or reuses the daemon. No local synchronization YAML, group or Kubernetes credentials are needed.

Use `shadok learn builds` for build/watch integration and `shadok learn verify` for HTTP checks. To remove the local job, run from this same project directory with the same gateway and CA values:

```sh
shadok unwatch --session "$NAMESPACE/$SESSION" --ca-file "$SYNC_CA"
```

This stops synchronization; restore production by setting the session's `spec.enabled` to false as shown in the runtime guide.

## Additional live volumes

Declare tools and extra mounts in `spec.volumes` of the DevelopmentSession. The operator attaches them only to the application container and removes them when restoring production. They are not exposed to the synchronization receiver. Do not patch the application Deployment beforehand.

Each entry has `name`, `mountPath`, optional `readOnly`, and exactly one source: `persistentVolumeClaim`, `configMap`, `secret`, or `files`. Existing Kubernetes resources must be in the session namespace. `files` provisions an emptyDir and downloads the declared HTTPS URLs with SHA256 verification before application startup. Each file requires `path` (a filename), `url`, and `sha256`. See `shadok learn spring` for a complete configuration.

Omit a directory's `imagePath` to create an empty working directory for initialization or synchronization. Set it when files must be copied from the application image.

### Optional live probes and resources

Add this under `spec` in the same session, replacing `APPLICATION_CONTAINER` with the existing container name. The values are examples to size for your application:

```yaml
  podTemplatePatch: |
    spec:
      containers:
        - name: APPLICATION_CONTAINER
          livenessProbe: null
          resources:
            requests:
              cpu: "500m"
            limits:
              cpu: "2"
```

This example disables liveness during live mode and changes CPU only. Readiness and memory remain inherited. Use the same Kubernetes fields to adjust probes instead of removing them. A startup probe protects initial startup, not subsequent reloads.

Keep the `|`: the patch is YAML text, so `null` deletions survive Helm and `kubectl apply`. The patch uses Kubernetes Strategic Merge Patch rules on the pod template: containers and environment variables merge by name, omitted fields are retained, and `null` removes a field. Lists without a merge strategy are replaced. The operator applies it to the saved production template before adding Shadok's command, mounts and synchronization containers; those session-managed settings take precedence. Deployment selectors and replicas are outside this patch.

Apply changes to the session to trigger a new rollout. Removing a patch field restores that production value; disabling the session restores the production template. No manual Deployment patch is required.
