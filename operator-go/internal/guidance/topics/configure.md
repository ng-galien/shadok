# Configure a live session and destination

Inspect the existing Deployment's container name, image paths, start command, UID/GID, readiness probes, imagePullSecrets and existing mounts. A session transforms that Deployment in place. It preserves routing labels, sidecars, environment, resources and volumes; mounting collisions and incompatible identities are rejected. Disable sessions before an application upgrade or GitOps change to the PodTemplate.

Example session for an existing non-root Node application named orders in team-a. Its image must contain /app/src and Node, and support UID/GID 1000. Adapt all runtime details to the application; Shadok does not supply Node.

```yaml
apiVersion: shadok.org/v1alpha1
kind: DevelopmentSession
metadata:
  name: orders-live
  namespace: team-a
spec:
  enabled: false
  deployment: orders
  container: app
  runAsUser: 1000
  runAsGroup: 1000
  directories:
    - name: application
      imagePath: /app/src
      mountPath: /app/src
  start:
    command: [node]
    args: [--watch, src/server.js]
    workingDir: /app
```

Save as session.yaml and apply with kubectl. `spec.deployment` is immutable and must name a Deployment in the same namespace. Directory names match local `roots[].mount`; imagePath is seeded from the application image, mountPath is its live destination. Paths must be absolute. An optional `spec.image` selects a development application image for both application and seed init container. `spec.imagePullPolicy` may override its policy. Disabling restores the original image/policy with the whole saved template.

Alternatively set `session.create: true` and the corresponding `session.*` chart values. Additional session-only Helm releases use `operator.enabled: false`; they must not install duplicate infrastructure.

Project-owned shadok.yaml contains portable groups and local paths, relative to the config file:

```yaml
version: 1
project: orders
groups:
  source:
    mode: watch
    roots:
      - mount: application
        path: src
        exclude: ["**/*.swp", "**/*~"]
```

Keep the personal destination outside committed project configuration. Set SHADOK_DESTINATIONS to an explicit YAML path (otherwise the OS user config directory contains shadok/destinations.yaml):

```yaml
version: 1
destinations:
  my-cluster:
    url: https://sync.example.com
    namespace: team-a
    deployment: orders
    # caFile: /absolute/path/to/private-ca.pem
```

```sh
export SHADOK_DESTINATIONS="$HOME/.config/shadok/destinations.yaml"
export SHADOK_DESTINATION=my-cluster
kubectl apply -f session.yaml
kubectl -n team-a patch developmentsession orders-live --type merge -p '{"spec":{"enabled":true}}'
kubectl -n team-a get developmentsession orders-live -o yaml
kubectl -n team-a rollout status deployment/orders --timeout=120s
shadok watch --config shadok.yaml --group source
shadok status
```

Check Ready=True and status.observedGeneration matches metadata.generation, then check rollout separately: Ready means the template was applied, not that the application is ready. Reliable application readiness matters for runtimes that initialize a reload watcher during startup.

The CLI starts/reuses a private local daemon. `watch` waits for the initial ACK then the daemon continues scanning once per second. Change a known response, inspect status for matching snapshot.manifest.revision and ack.revision with no error, and request the application through its normal route. Check a replacement Pod also receives the revision. Explicit destination flags are also supported: `--url`, `--namespace`, `--deployment`, `--ca-file`. No kubeconfig is used by this sync path. Developer Kubernetes permission can be limited to session resources; operator and gateway use separate service accounts.

Stop a group with the same config, group and destination: `shadok unwatch --config shadok.yaml --group source`. This removes its retained snapshot but does not disable its Kubernetes session. `shadok daemon stop` stops the process but retains saved jobs and snapshots in its state directory. The next CLI command that starts the daemon resumes those jobs. Use `unwatch` before stopping when a group must not resume. If retained state was removed or a snapshot is missing, run watch/publish again to recreate it. SHADOK_STATE_DIR selects the private local daemon directory; default is the OS user cache directory plus shadok.

## Spring production/live walkthrough

Run `shadok learn spring` (or `shadok docs spring`) for the complete production-to-DevTools procedure, including a platform-prepared read-only DevTools volume with no image override, the separate-live-image alternative, build publication, class additions/deletions and production restoration.
