# Connect the daemon to the synchronization gateway

## Follow the network path

```text
Workstation / CI runner: Shadok CLI and daemon
  -> https://sync.example.com/team-a/orders/plan or /apply
  -> platform Ingress controller (DNS, external address, TLS)
  -> Shadok gateway Service (port 80 by default)
  -> gateway container (port 8080)
  -> ready application pod synchronization receiver (port 7777)
```

The operator configures live pods through the Kubernetes API; it does not receive build uploads. The gateway uses read-only Kubernetes access to resolve the enabled session and ready receivers for a namespace/Deployment. It discovers their changing IP addresses and forwards changes to the receivers. Do not configure pod IPs in the daemon.

The application's own Service/Ingress is separate. Use the **gateway URL** for file synchronization and the **application URL** to verify behavior after reload. An application returning HTTP 200 does not prove the gateway is reachable; a synchronization ACK does not prove application reload.

## Platform: expose the gateway

The platform administrator installs Shadok infrastructure and configures networking. Developers can retain CR-only Kubernetes permissions: their daemon needs network access to the gateway, not a kubeconfig, pod access or port-forward permissions.

The Shadok chart creates an Ingress resource when enabled. It does **not** install an Ingress controller, provision DNS records or automatically issue certificates. Before configuring it, identify:

- The existing Ingress controller and its IngressClass.
- Its address reachable from the workstation/CI runner, including any required VPN/private network.
- A DNS hostname resolving to that address, not a pod IP or an internal-only ClusterIP.
- A certificate for that hostname and its TLS Secret in the Shadok installation namespace.
- The existing application namespace and exact Deployment name.

For an existing installation, merge these settings into its existing values file; retain image references, namespace scope and other platform settings. Example for Helm release `shadok` in namespace `shadok-system`:

```yaml
operator:
  watchNamespaces: [team-a]
service:
  type: ClusterIP
  port: 80
# TLS terminates at the Ingress; the gateway backend serves HTTP.
gateway:
  tlsSecretName: ""
ingress:
  enabled: true
  className: traefik
  host: sync.example.com
  tlsSecretName: sync-tls
```

Replace the class and hostname with actual platform values. The TLS Secret belongs in `shadok-system`, where the Ingress is created. `sync.example.com` must resolve to the Ingress controller's reachable address. The default Ingress path `/` preserves the full `/team-a/orders/plan` and `/apply` paths. Do not add a rewrite that strips the namespace or Deployment, and do not place an extra prefix in the daemon URL.

Install using the matching exported or release chart and the complete values file, as described in `shadok learn install`. For example, after exporting the chart:

```sh
helm upgrade --install shadok ./shadok-chart -n shadok-system --create-namespace \
  -f deployment-values.yaml --wait --timeout 5m
kubectl -n shadok-system get ingress,service,pods
kubectl -n shadok-system describe ingress shadok-shadok
```

The resource name above follows the chart's default release-name convention; use the names shown by `kubectl get` if overridden. Cluster context must be selected explicitly or confirmed before running platform commands. The application's Deployment and its namespace must already exist. The gateway/receiver route becomes available only after the session is enabled and the application pod is ready.

TLS at the Ingress is the simplest example. If `gateway.tlsSecretName` is set, the gateway itself serves HTTPS, and the Ingress controller must be configured for an HTTPS backend using its own supported settings. Do not mix an HTTP backend configuration with a TLS-enabled gateway.

### Alternatives and local addresses

- **ClusterIP:** usable only from a machine with network/DNS access to cluster services. It does not expose the gateway to an ordinary workstation.
- **NodePort:** set `service.type: NodePort` and a platform-chosen `service.nodePort`; the client uses a reachable node address and that port. Node addresses, firewall rules and Kind host mappings are platform concerns. Configure native gateway TLS or a trusted TLS proxy for HTTPS.
- **LoadBalancer:** set `service.type: LoadBalancer`; the platform's load balancer implementation assigns/exposes an address. Point DNS to it and configure TLS appropriately. The chart does not create a load balancer implementation.
- **Kind on macOS:** Docker node addresses are not necessarily directly reachable from the host. Provide host-port mappings or the documented local relay/Ingress setup. The repository's `docs/LOCAL_INGRESS.md` contains a tested Traefik/nip.io setup with HTTPS on port 8443. A `127.0.0.1.nip.io` hostname points to the caller's own machine, so it is not a usable remote CI address.

`service.clusterIP` is an internal Service allocation; it is not the public IP for an Ingress. Usually leave it unset. TLS certificate names must match the hostname clients use, including when a nip.io name is used.

## Developer / CI: select the destination

Save destination settings outside committed project configuration, for example in `~/.config/shadok/destinations.yaml`:

```yaml
version: 1
destinations:
  team-dev:
    url: https://sync.example.com
    namespace: team-a
    deployment: orders
    # Only for a private CA; use a real absolute path:
    # caFile: /absolute/path/to/company-ca.pem
```

`url` is the gateway origin, with a non-default port if needed. Do not append `/team-a/orders`, `/plan` or `/apply`: the daemon appends these itself. `deployment` is the existing Deployment name, not the DevelopmentSession resource name or Helm release. Namespace is the application's namespace, not the operator installation namespace.

```sh
export SHADOK_DESTINATIONS="$HOME/.config/shadok/destinations.yaml"
export SHADOK_DESTINATION=team-dev
# From the application directory, using its configured build group:
shadok build --config shadok.yaml --group service -- mvn verify
shadok status
```

Use the actual project's build command/group. For a source watch group use `shadok watch --config shadok.yaml --group source`. Explicit flags are also supported:

```sh
shadok publish --config shadok.yaml --group service \
  --url https://sync.example.com --namespace team-a --deployment orders
```

Add `--ca-file /absolute/path/to/company-ca.pem` when required. The daemon performs certificate verification; do not work around trust failures by disabling verification. CI runners need the same DNS/network reachability and CA trust as workstations. Their Kubernetes credentials are not used for synchronization.

## Traffic rules and limits

Allow workstation/CI traffic to the exposed gateway endpoint, Ingress-to-gateway traffic on the configured backend port, gateway-to-receiver TCP 7777 in the watched application namespaces, and operator/gateway access to the Kubernetes API. NetworkPolicies in application namespaces must permit receiver traffic separately. The Shadok chart cannot infer your CNI, API/service CIDRs or corporate firewall rules.

Keep the gateway behind the platform's trusted access boundary. Built-in writer authentication is not implemented; TLS and the namespace/Deployment URL are not authentication. The CLI does not implement interactive SSO or arbitrary authentication headers. Do not assume a browser login page will work for the daemon.

Ingress/proxy request sizes and timeouts must fit build uploads. The receiver supports up to 512 MiB per revision; the gateway request bound is 544 MiB including overhead. The daemon currently uses a 45-second HTTP request timeout; increasing an Ingress timeout alone does not extend that budget. Controller-specific upload limits, buffering and timeout settings belong in the platform configuration. See the repository's local Ingress guide for the concrete tested Traefik settings and their test limits.

## Verify and diagnose in order

1. Confirm DNS resolves to an address reachable from the actual workstation or CI runner. A loopback address only reaches that same machine.
2. Verify TLS for the chosen hostname. `curl --cacert /path/to/ca.pem -v https://sync.example.com/` can inspect connectivity/TLS, but a 404 on `/` is not a failed synchronization test: the gateway expects POST requests to `/namespace/deployment/plan` and `/apply`.
3. Confirm Ingress backend protocol, Service endpoints and the enabled session. The platform inspects gateway logs and pod readiness; the developer can inspect the session CR. Ready on the session means template application, not completed application startup.
4. Publish a completed build through the CLI, then inspect `shadok status` for matching snapshot and ACK revisions without errors. Do not use an empty/manual `/apply` request as a connectivity probe.
5. Call the application's normal URL and verify the changed behavior. Keep this separate from the gateway address.

Typical failures:

- DNS error, refused connection or timeout: hostname, network/VPN, exposed port, firewall or Kind host mapping.
- Certificate failure: hostname mismatch, missing/private CA, expired certificate or wrong TLS endpoint.
- 404: wrong host/path/rewrite or backend; `/` alone legitimately returns 404 from the gateway.
- 409: gateway cannot resolve an enabled unambiguous session with ready live receivers; inspect the response and session/readiness.
- 413: proxy or gateway upload limit exceeded; identify which component rejected it.
- 502/503 or HTML login response: backend protocol/endpoints, proxy access policy or receiver connectivity; consult proxy/gateway logs rather than assuming a runtime reload problem.
- ACK with stale application response: inspect the application's command, mounted files and reload configuration using `shadok learn builds` or `shadok learn spring`.
