# Shadok Helm chart

The chart installs the Go controller, an independently scalable HTTP gateway, separate service accounts/RBAC, and the `DevelopmentSession` CRD. It can also create a session for an existing application Deployment. It does not build application images or select language runtimes.

Requires Helm 3 or 4 and Kubernetes 1.34 or newer. Local integration is tested on Kubernetes 1.36; rendering is tested with Helm 4.2.4. Image repositories in the source chart are **local placeholders**, not a claim that a public image exists. Use a release package with your registry prefix, or set repositories/tags/digests explicitly.

```sh
helm lint operator-go/chart --strict
make -C operator-go chart-test
helm upgrade --install shadok operator-go/chart -n shadok-system --create-namespace \
  --set operator.image.repository=registry.example.com/shadok/operator \
  --set gateway.image.repository=registry.example.com/shadok/gateway \
  --set operator.toolImage.repository=registry.example.com/shadok/tools \
  -f deployment-values.yaml --wait --timeout 5m
helm test shadok -n shadok-system --logs
```

## Configuration reference

`values.yaml` lists every setting; `values.schema.json` rejects unknown configuration keys and validates image digests, ports, names and basic types. Kubernetes-native extension objects (resources, probes, affinity, security contexts, extra volumes/env) are open schemas and are validated by Kubernetes. Rendering tests are in `../test/chart` and do not require an extra Helm plugin.

| Values | Purpose |
| --- | --- |
| `nameOverride`, `fullnameOverride` | Resource naming. Deployment selectors are stable across upgrades. |
| `commonLabels`, `commonAnnotations` | Resource metadata. Component-specific metadata can extend it. |
| `imagePullSecrets` | Existing registry secrets in the operator namespace, including Helm test/hook pods. |
| `operator.image`, `gateway.image`, `operator.toolImage` | `{repository, tag, digest}`; digest wins, empty tag uses chart appVersion. Complete image reference strings also work. |
| `operator.imagePullPolicy`, `gateway.imagePullPolicy` | Always, IfNotPresent or Never. |
| `operator.enabled` | Disable infrastructure to install only an application session. |
| `operator.watchNamespaces` | Empty means all namespaces with ClusterRoles; otherwise cache and gateway are scoped and Roles/Bindings are created in the listed existing namespaces. |
| `rbac.create`, `serviceAccounts.*` | Use generated or pre-existing permissions/accounts. Existing accounts must have the documented equivalent permissions. |
| `operator.leaderElection`, `operator.replicas` | Lease-based controller leadership. More than one replica requires election. Do not run independent overlapping installations with different leases. |
| `operator.*`, `gateway.*` | Per-component resources, pod labels/annotations, Deployment annotations, probes, security contexts, nodeSelector, tolerations, affinity, topology spread, priority, termination grace, strategy, environment and volumes. |
| `*.tmpSizeLimit` | Writable `/tmp` emptyDir while the root filesystem remains read-only. |
| `*.pdb` | Optional policy/v1 budget. Configure exactly one of minAvailable/maxUnavailable (set the other to null). A one-replica budget can deliberately block voluntary eviction. |
| `gateway.autoscaling` | autoscaling/v2 CPU/memory utilization targets, min/max replicas and behavior. Requires metrics-server and corresponding resource requests. |
| `service.*` | ClusterIP, NodePort or LoadBalancer, ports, IP/class, source ranges and traffic policies. |
| `gateway.tlsSecretName` | Existing TLS secret for native gateway TLS. Otherwise gateway serves HTTP for ingress termination. |
| `ingress.*` | Class, annotations, labels, simple host/TLS secret or multiple `hosts[].paths[]` and `tls[]`. Paths must preserve `/namespace/deployment/...`; do not strip them. |
| `metrics.*` | Optional controller metrics service and Prometheus ServiceMonitor (requires its CRD). |
| `networkPolicy.*` | Optional controller/gateway ingress and egress policies. Explicit API server/service CIDRs required. Gateway egress permits receivers on 7777 in the watched namespaces. |
| `tests.*` | Helm connection test pod; configurable test image. Tests TCP reachability, not full synchronization. |
| `uninstallGuard.*` | Pre-delete Job rejects uninstall while sessions are enabled or still restoring; reads through the operator account. |
| `session.*` | Optional DevelopmentSession with namespace, labels/annotations, target, directories, command, UID/GID and live image override. |

Example settings for HA and a private registry:

```yaml
imagePullSecrets: [{name: registry-pull}]
operator:
  replicas: 2
  watchNamespaces: [team-a, team-b]
  image: {repository: registry.example.com/shadok/operator, tag: "1.0.0"}
  toolImage: {repository: registry.example.com/shadok/tools, tag: "1.0.0"}
  podAnnotations: {example.com/owner: platform}
  pdb: {enabled: true, minAvailable: 1}
gateway:
  image: {repository: registry.example.com/shadok/gateway, tag: "1.0.0"}
  autoscaling: {enabled: true, minReplicas: 2, maxReplicas: 5}
  pdb: {enabled: true, minAvailable: 1}
ingress:
  enabled: true
  className: traefik
  host: sync.example.com
  tlsSecretName: sync-tls
```

The source images have no implicit public publication. Replace all example registry names and use versions/digests you have built and pushed.

## Custom images and bases

There are three independent choices:

1. Build Shadok binaries with a custom compiler image using Docker `--build-arg BUILD_IMAGE=...` (Go 1.26+ and a working toolchain).
2. Build the three Shadok runtime images with `--build-arg RUNTIME_IMAGE=...`. The binaries are statically compiled; the base must support the target architecture and non-root UID 65532. HTTPS needs CA certificates. Runtime bases are selected **at image build time**, never by Helm.
3. Set `session.image` to a custom development application image. The app and seed init container use it; disabling restores the original image and pull policy. `session.imagePullPolicy` optionally overrides the original policy. The image must contain the configured paths and command and support the requested UID/GID.

Live pods inherit the application's `imagePullSecrets`. Install credentials for private tools/development images in each application namespace and reference them on its baseline Deployment. Operator-namespace secrets cannot be used cross-namespace.

## Network and lifecycle

Gateway authentication is not built in. Protect access at the ingress/proxy or trusted network boundary. Size request limits and timeouts for the archive workload; TLS termination alone does not authenticate writers. The local Traefik example and real upload tests are documented in `docs/LOCAL_INGRESS.md` in the source repository. Native gateway TLS behind an ingress also requires the ingress controller's HTTPS-backend configuration; annotations vary by controller.

NetworkPolicy requires an enforcing CNI. Empty `gatewayIngressFrom`/`metricsIngressFrom` permits any source on the listed ports; populate selectors/IP blocks for your platform. API service and endpoint addresses may both be needed depending on CNI NAT ordering. Application namespace policies must permit gateway-to-receiver traffic separately; the chart does not take ownership of application networking. Node probes and DNS arrangements should be checked on the target CNI.

Before an upgrade, back up the CRs and baseline ConfigMaps, review CRD schema changes, apply `chart/crds` explicitly, then upgrade the release. Helm installs CRDs from `crds/` but does not upgrade or delete them. Do not use force replacement to work around CRD compatibility failures. Schema changes must remain compatible with existing sessions; no conversion webhook is provided.

Before uninstall, set every managed session to `enabled: false` and wait for `Ready=True` with reason `Baseline` and the finalizer to disappear. Check application rollouts. The hook blocks uninstall until this is done; do not bypass it with `--no-hooks` during live sessions. A failed hook Job remains for diagnosis and is replaced on retry. Helm rollback changes chart resources, not already-applied CRD schemas or application source content. Test upgrades and rollback with the versions used by your platform.

References: [Helm CRD lifecycle](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/), [chart schema](https://helm.sh/docs/topics/charts/), [OCI registries](https://helm.sh/docs/topics/registries/).
