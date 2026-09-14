# Restore, delete and troubleshoot

## Restore production

Run from the same project directory used for publication/watch. Reuse its gateway URL and CA file. Replace the example namespace, session and Deployment below with your target.

```sh
export SHADOK_URL=https://sync.example.com
export SYNC_CA="" # Use the same absolute CA file path as publication, if any.
shadok unwatch --session team-a/orders-live --ca-file "$SYNC_CA"
kubectl -n team-a patch developmentsession orders-live --type merge -p '{"spec":{"enabled":false}}'
kubectl -n team-a get developmentsession orders-live -o yaml
```

Check `Ready=True`, `reason: Baseline` and `status.observedGeneration` equal to `metadata.generation`. Then check the rollout and application response:

```sh
kubectl -n team-a rollout status deployment/orders --timeout=120s
```

## Delete a session

```sh
kubectl -n team-a delete developmentsession orders-live
kubectl -n team-a get deployment orders -o yaml
```

Wait for the `shadok.org/live-session` annotation to disappear, then check rollout and the production endpoint. Deletion does not wait for cleanup. If the operator is stopped, cleanup resumes when it starts.

For pending cleanup, inspect:

```sh
kubectl -n team-a get configmaps -l shadok.org/recovery-session
kubectl -n shadok-system logs deployment/shadok --tail=100
```

Use your installation's operator Deployment name. Keep recovery ConfigMaps until cleanup completes. A session carrying `shadok.org/restore-baseline` is handled automatically; do not remove other controllers' finalizers.

## Uninstall

Restore all managed sessions and verify application rollouts before running:

```sh
helm uninstall shadok -n shadok-system
```

If the uninstall hook fails, inspect its Job logs, restore the sessions it reports and retry. Remove the CRD only when no installation uses it.

## Update

Run `shadok learn upgrade` for CLI and cluster update commands.

## Diagnose

| Symptom | Check |
| --- | --- |
| Session not ready | Session conditions, target container, directory paths and pod init logs |
| Sync target missing | Session namespace/name, enabled session and ready application pods |
| TLS error | Gateway hostname and CA; supply `--ca-file` for a private CA |
| Transfer rejected | Ingress upload limits, gateway logs and network access |
| ACK but unchanged app | Runtime reload command and application HTTP response |
| Stale local job | `shadok status`; stop the job with `shadok unwatch` and publish again |

For framework setup use `shadok learn spring`; for gateway setup use `shadok learn network`.
