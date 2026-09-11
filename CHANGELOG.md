# Changelog

## 1.1.0

- Add offline `shadok learn spring` and `shadok learn network` guides covering live activation, production restoration, gateway exposure, DNS/TLS and daemon destinations.
- Add a Spring example that keeps the production image and loads DevTools from a platform-prepared read-only PVC. Live validation covers adding a controller method, adding/removing a controller and restoring production. The operator preserves the existing mount; it does not provision this PVC.
- Isolate sample build tooling and update the six sample run guides.
- Lower the chart Kubernetes floor from 1.34 to 1.25, based on the existing CRD CEL transition rule. Runtime integration is validated on 1.36.1; this does not claim testing every intervening version.

The CRD remains `v1alpha1`. Built-in writer authentication, parallel A/B routing and session-managed additional volume mounts are not implemented.

CLI archives, images and the OCI chart use version `1.1.0`. See [installation](https://github.com/ng-galien/shadok/blob/main/docs/INSTALL_RELEASE.md) and [Spring volume evidence](https://github.com/ng-galien/shadok/blob/main/docs/SPRING_VOLUME_VALIDATION.md).

## 1.0.0

- Replace the former Java operator with a Go operator for generic existing Deployments. Preserve Java demo applications.
- Add the Shadok CLI, local synchronization daemon and gateway, with source watching and successful-build publication hooks.
- Package a configurable Helm chart with schema validation, chart unit tests and installation, upgrade, rollback and restoration checks.
- Embed operational documentation and chart export in the CLI. Provide a minimal model-independent skill that routes agents to `shadok learn`.
- Add local release packaging for macOS/Linux on AMD64/ARM64, container build-base overrides, checksums and tag-only publication with source-version and main-branch ancestry checks.
- License Shadok under MIT.

The Kubernetes API remains `v1alpha1`. The gateway requires a trusted network or platform access control; it does not provide built-in writer authentication. See `docs/VALIDATION.md` for tested behavior and limits.

## Install 1.0.0 (historical)

Download the CLI archive for your OS/architecture and verify it using `SHA256SUMS-1.0.0`. The CLI includes offline guides: `shadok learn`.

```sh
helm upgrade --install shadok oci://ghcr.io/ng-galien/shadok/charts/shadok \
  --version 1.0.0 -n shadok-system --create-namespace \
  -f deployment-values.yaml --wait
```

See [installation and Kind setup](https://github.com/ng-galien/shadok/blob/main/docs/INSTALL_RELEASE.md). Requires Helm 3/4 and Kubernetes 1.34+. Images support Linux AMD64/ARM64; CLI supports macOS/Linux AMD64/ARM64. Configure the gateway on a trusted network before syncing. Public registry availability and fresh Kind installation are verified: see [consumer validation](https://github.com/ng-galien/shadok/blob/main/docs/releases/1.0.0-validation.md).
