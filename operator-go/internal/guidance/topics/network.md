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
- Preserve `/namespace/deployment/plan` and `/namespace/deployment/apply`; do not strip these paths.
- This example terminates TLS at the Ingress. If enabling gateway TLS, configure an HTTPS backend too.
- Allow gateway-to-application TCP 7777 and operator/gateway access to the Kubernetes API.
- Restrict gateway access to a trusted network or compatible authentication proxy.
- Configure upload limits for your builds: up to 512 MiB per revision, 544 MiB including request overhead. The daemon request timeout is 45 seconds.

For local Kind with Traefik/nip.io, follow `docs/LOCAL_INGRESS.md`. A loopback hostname cannot be used by a remote CI runner.

## Developer / CI: select the destination

Save `~/.config/shadok/destinations.yaml`:

```yaml
version: 1
destinations:
  team-dev:
    url: https://sync.example.com
    namespace: team-a
    deployment: orders
    # For a private CA:
    # caFile: /absolute/path/to/company-ca.pem
```

Use the gateway origin only: do not append namespace or endpoint paths. Set the application's namespace and Deployment name, not the operator namespace or session name.

```sh
export SHADOK_DESTINATIONS="$HOME/.config/shadok/destinations.yaml"
export SHADOK_DESTINATION=team-dev
shadok build --config shadok.yaml --group service -- mvn verify
shadok status
```

Replace the group and build command with your project's settings. For source synchronization, use `shadok watch --config shadok.yaml --group source`.

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
