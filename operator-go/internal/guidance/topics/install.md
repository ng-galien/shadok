# Install the operator from the binary

Requirements: Helm 3 or 4, kubectl, Kubernetes 1.25+, an existing application Deployment, and accessible operator/gateway/tools images matching this CLI release. Inspect the selected context and existing installations before changing anything. Avoid overlapping controllers with independent leader-election leases.

```sh
shadok version
kubectl config current-context
kubectl get namespaces
helm list --all-namespaces
kubectl get deployments -n team-a
kubectl get deployment orders -n team-a -o yaml
shadok chart export ./shadok-chart
helm show values ./shadok-chart
```

Choose the intended context explicitly for subsequent kubectl (`--context`) and Helm (`--kube-context`) commands. The examples assume that context has already been selected and authorized. The application namespace must exist. Scoped installs create permissions there; cluster CRD installation still needs cluster-level permission.

Save deployment-values.yaml, replacing registry, version, namespaces, ingress class and hostname with actual platform values:

```yaml
operator:
  watchNamespaces: [team-a]
  image: {repository: registry.example.com/shadok/operator, tag: "1.1.0"}
  toolImage: {repository: registry.example.com/shadok/tools, tag: "1.1.0"}
gateway:
  image: {repository: registry.example.com/shadok/gateway, tag: "1.1.0"}
ingress:
  enabled: true
  className: traefik
  host: sync.example.com
  tlsSecretName: sync-tls
```

These registry names are examples, not published defaults. Check `shadok docs values` for all settings. Create the existing TLS secret through the platform's certificate workflow. For private registries, `imagePullSecrets` applies in the operator namespace; application Deployments must separately reference secrets in their own namespace for the tools and optional live image. TLS alone does not authenticate writers: the gateway has no built-in authentication. Use a trusted network or compatible platform access control. The CLI does not currently implement arbitrary auth headers or an interactive SSO login.

```sh
helm lint ./shadok-chart --strict -f deployment-values.yaml
helm template shadok ./shadok-chart -n shadok-system -f deployment-values.yaml > rendered.yaml
# Review rendered.yaml, then install in the intended cluster:
helm upgrade --install shadok ./shadok-chart -n shadok-system --create-namespace \
  -f deployment-values.yaml --wait --timeout 5m
helm test shadok -n shadok-system --logs
kubectl -n shadok-system get deployments,pods,services,ingresses
```

The chart installs separate operator and gateway workloads. Its default source image names are placeholders: explicit image references are required for a real cluster. `operator.replicas: 2` supports HA with leader election enabled. `gateway.autoscaling` requires metrics-server and resource requests; `metrics.serviceMonitor` requires the Prometheus CRD. NetworkPolicy requires an enforcing CNI and real API server/service CIDRs. Read `shadok docs chart` before enabling those features.

Preserve `/namespace/deployment/plan` and `/namespace/deployment/apply` paths at the ingress. Set request sizes/timeouts for the artifacts (up to 512 MiB per revision plus archive overhead). Native TLS is available through `gateway.tlsSecretName`; an ingress in front then needs its controller-specific HTTPS-backend configuration. Do not disable certificate verification: use `--ca-file` for a private CA.

The binary exports a chart, not image build sources. To customize compiler/runtime base layers, a maintainer builds a release from source with Docker BUILD_IMAGE (Go 1.26+) and RUNTIME_IMAGE build arguments, then supplies the three images. To use already-built custom operator/gateway/tools images, set their chart image objects directly; digest takes precedence over tag. To change only the live application image, set the session image described in `shadok docs configure`.
