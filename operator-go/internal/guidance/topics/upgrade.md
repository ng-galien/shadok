# Update Shadok

## CLI

```sh
shadok upgrade cli
shadok version
```

Use `--version VERSION` to select a published release, or `--output PATH` to install elsewhere. The command verifies SHA256 before replacing the binary. Its installation directory must be writable.

If a daemon is running:

```sh
shadok daemon stop
# Restart your usual build/watch command.
```

If `upgrade` is unavailable, install the CLI from the release archive.

## Operator and gateway — platform administrator

Requirements: a CLI from the target release, Helm, kubectl and cluster permissions. Replace the context, namespace and release name below.

```sh
shadok upgrade cluster --context company-dev \
  --namespace shadok-system --release shadok --dry-run

shadok upgrade cluster --context company-dev \
  --namespace shadok-system --release shadok \
  --backup-dir ./shadok-before-upgrade
```

The backup directory must be new. Without `--backup-dir`, the command prints the temporary backup directory it creates.

Operational Helm values and image repositories are retained. Operator, gateway and tools tags advance to the CLI version; existing digests are cleared. For approved image or configuration overrides, add:

```sh
--values platform-values.yaml
```

The command applies the embedded CRD, upgrades the existing Helm release and waits for rollout. Use `--timeout 10m` if needed. `--dry-run` renders the chart and validates the CRD without applying resources.

## Verify

```sh
helm --kube-context company-dev -n shadok-system status shadok
kubectl --context company-dev -n shadok-system get deployments,pods
```

Run a build/sync and check an application endpoint.

If the upgrade fails, inspect the reported error and the saved values/manifests. The backup is retained. A Helm rollback does not roll back an applied CRD.
