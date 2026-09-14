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
