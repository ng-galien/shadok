# Configure the synchronization gateway

## Platform: expose the gateway

Prepare an Ingress controller, a reachable DNS hostname and a TLS Secret in the Shadok namespace. Add to the installation's values file:

```yaml
operator:
  watchNamespaces: [team-a]
service:
  type: ClusterIP
  port: 80
gateway:
  tlsSecretName: ""
ingress:
  enabled: true
  className: traefik
  host: sync.example.com
  tlsSecretName: sync-tls
```

Replace the hostname, class and namespace. Keep the installation's image settings. Apply with the matching chart:

```sh
helm upgrade --install shadok ./shadok-chart -n shadok-system --create-namespace \
  -f deployment-values.yaml --wait --timeout 5m
kubectl -n shadok-system get ingress,service,pods
```

Select the intended Kubernetes context before running these commands.

- Point DNS at the reachable Ingress address; do not configure pod IPs.
- Preserve `/sessions/namespace/session-name` and its `/plan` and `/apply` paths; do not strip these paths. Legacy clients also use `/namespace/deployment/plan` and `/namespace/deployment/apply`.
- This example terminates TLS at the Ingress. If enabling gateway TLS, configure an HTTPS backend too.
- Allow gateway-to-application TCP 7777 and operator/gateway access to the Kubernetes API.
- Restrict gateway access to a trusted network or compatible authentication proxy.
- Configure upload limits for your builds: up to 512 MiB per revision, 544 MiB including request overhead. The daemon request timeout is 45 seconds.

For local Kind with Traefik/nip.io, follow `docs/LOCAL_INGRESS.md`. A loopback hostname cannot be used by a remote CI runner.

## Developer / CI: select the destination

Run from the project root. Use the gateway origin and the namespace/name of the `DevelopmentSession`:

```sh
export SHADOK_URL=https://sync.example.com
export SYNC_CA="" # Set an absolute PEM CA path only for a private gateway CA.
shadok build --session team-a/orders-live --ca-file "$SYNC_CA" -- mvn clean verify
shadok status
```

The session declares each local output with `spec.directories[].localPath`, relative to this project root. No local configuration file or group is required. The gateway resolves the session's target Deployment and receivers.

For already built files, use `shadok publish --session team-a/orders-live --ca-file "$SYNC_CA"`. For source synchronization, use `shadok watch --session team-a/orders-live --ca-file "$SYNC_CA"`. Set `SYNC_CA` to the absolute PEM CA path if your gateway uses a private CA; otherwise leave it empty. To stop this job, run `shadok unwatch --session team-a/orders-live --ca-file "$SYNC_CA"` from the same project directory with the same gateway and CA values.

The workstation/runner needs gateway network access and CA trust; synchronization does not use Kubernetes credentials.

## Read synchronization failures

`publish`, `build` and `watch` print delivery errors to stderr while retrying. A timeout includes the last failure and the daemon log path. Run `shadok status` to inspect the job's destination, `error`, `updated` and acknowledgement. The daemon logs changes in failure state and recovery, without repeating the same error every second.

A platform administrator can read gateway errors:

```sh
kubectl -n shadok-system logs deployment/shadok-gateway --since=10m
```

Replace the namespace and gateway Deployment name with the installation's values. Gateway failure logs include the HTTP method, route, status and cause. Receiver failures also identify the pod and upstream status. No request headers or upload contents are logged. If the gateway has no matching request, check the client error and the ingress/proxy logs first.

## Verify and troubleshoot

Publish a build, inspect `shadok status`, then call the application's URL. Use the gateway URL for synchronization and the application URL for HTTP checks.

| Failure | Check |
| --- | --- |
| Connection refused/timeout | DNS, VPN, exposed port and firewall |
| Certificate error | Hostname, expiry and `caFile`/`--ca-file` |
| 404 | Host/path rewriting; `/` alone may return 404 |
| 409 | Enabled session and ready application receivers |
| 413 | Ingress/gateway upload limit |
| 502/503 or HTML login page | Proxy policy, backend protocol and gateway logs |
| ACK but stale application | Runtime command and reload configuration; `shadok learn spring` |

### Logs for each component

- Local daemon: the `daemon.log` path printed on a failed publication. It records startup, state-file failures, sync failures, recovery and acknowledged revisions. `shadok status` shows the latest job error.
- Gateway: `kubectl -n <operator-namespace> logs deployment/<gateway-deployment> --since=10m`. Requests include method, path, HTTP status and duration; failures include the downstream cause.
- Receiver: `kubectl -n <application-namespace> logs <live-pod> -c shadok-sync --since=10m`. Look for plan, revision applied, mount validation and filesystem errors.
- Operator: `kubectl -n <operator-namespace> logs deployment/<operator-deployment> --since=10m`. Look for session transition errors and completed transitions.
- Initialization: `kubectl -n <application-namespace> get pod <live-pod> -o jsonpath='{.spec.initContainers[*].name}'`, then `kubectl -n <application-namespace> logs <live-pod> -c <init-container>`. Tool preparation logs identify the file and destination.

For a restarted container, add `--previous`. If the container never started, inspect `kubectl -n <application-namespace> describe pod <live-pod>` for image, scheduling and volume-mount errors. An administrator can collect these logs when your account has no pod access.
