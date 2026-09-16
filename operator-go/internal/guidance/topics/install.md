# Install the operator

Requirements: Helm 3/4, kubectl, Kubernetes 1.30+, an existing application Deployment and cluster installation permissions. Use published images matching the CLI version.

## Prepare

```sh
shadok version
kubectl config current-context
helm list --all-namespaces
shadok chart export ./shadok-chart
helm show values ./shadok-chart
```

Select the intended context. Create `deployment-values.yaml` with your registry, version and application namespace:

```yaml
operator:
  watchNamespaces: [team-a]
  image: {repository: registry.example.com/shadok/operator, tag: ""}
  toolImage: {repository: registry.example.com/shadok/tools, tag: ""}
gateway:
  image: {repository: registry.example.com/shadok/gateway, tag: ""}
```

An empty tag selects the exported chart's `appVersion`; verify your mirror contains that version. Use `shadok docs values` for all options. Configure gateway exposure with `shadok learn network`. For private registries, provide image-pull credentials in both the installation and application namespaces.

## Install and verify

```sh
helm lint ./shadok-chart --strict -f deployment-values.yaml
helm template shadok ./shadok-chart -n shadok-system -f deployment-values.yaml > rendered.yaml
helm upgrade --install shadok ./shadok-chart -n shadok-system --create-namespace \
  -f deployment-values.yaml --wait --timeout 5m
helm test shadok -n shadok-system --logs
kubectl -n shadok-system get deployments,pods,services,ingresses
```

Review `rendered.yaml` before installation. Keep gateway access restricted; built-in writer authentication is unavailable.

Next: choose your complete application guide with `shadok learn`. For updates, use `shadok learn upgrade`.

## Session permissions

The operator chart enables a fail-closed admission policy. The platform configures sessions with an identity that can patch their target Deployments; developers can be granted only activation of an existing session. Before delegating access, follow `shadok learn rbac` to install and inspect the policy, review existing sessions, bind named identities, verify permitted and denied operations, and protect the HTTP gateway separately. An application-only chart does not install this policy.
