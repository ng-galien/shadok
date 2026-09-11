# Verify, restore, upgrade and troubleshoot

## Restore and uninstall

Stop the local producer for the exact group/destination, disable the session, and wait for the operator to restore the saved baseline:

```sh
shadok unwatch --config shadok.yaml --group source
kubectl -n team-a patch developmentsession orders-live --type merge -p '{"spec":{"enabled":false}}'
kubectl -n team-a get developmentsession orders-live -o yaml
kubectl -n team-a rollout status deployment/orders --timeout=120s
```

Confirm status.observedGeneration matches metadata.generation, Ready=True has reason Baseline, and the Shadok finalizer is gone. Do not use `kubectl wait --for=condition=Ready` alone: the previous live generation may already have Ready=True. Compare the restored PodTemplate and application response with the baseline. Restore every session managed by this installation before `helm uninstall shadok -n shadok-system`. The pre-delete guard blocks unsafe removal; inspect its failed Job logs, restore the remaining sessions, then retry. Do not bypass active-session protection with --no-hooks or remove finalizers to force deletion.

Helm retains the CRD. Remove it only after all sessions have been restored and deleted and no other installation uses it. Session deletion while the operator runs also restores via its finalizer. Never delete the baseline ConfigMap to resolve a restore error.

## Upgrade

Save current release values, sessions and their owned baseline ConfigMaps. Prefer disabling sessions before operator/application upgrades. Use a matching new CLI to export its chart to a new directory, inspect schema changes and image references, then explicitly apply the exported chart/crds before `helm upgrade`. Helm does not upgrade existing CRDs. Review compatibility first; do not force schema replacement. Run `helm test`, enable a controlled session, test a revision/application response, then restore it. Helm rollback rolls back chart resources, not CRD schema changes or already-transferred source files.

## Troubleshooting

- Installation: inspect `helm status`, workload events, image pull errors and rollout status. Source-chart image names are placeholders. Check actual tags/digests, architecture and registry credentials in each relevant namespace.
- Session not ready: inspect the CR's conditions, observedGeneration and operator logs. Verify Deployment/container, directory paths, UID/GID, volume collisions, immutable target and another active session. Check Pod init logs for tool/seed failures.
- Sync 404/target absent: confirm destination namespace/deployment, scoped operator watchNamespaces, session enabled, application Pods ready and receiver running. Preserve route prefixes at ingress. Do not change the CLI destination to a Pod IP to hide a discovery issue.
- TLS: verify gateway hostname and certificate chain; configure a private CA with caFile/--ca-file. Native TLS requires HTTPS upstream support at the ingress. The gateway has no built-in authentication and the client has no SSO flow.
- 413 or timeout: inspect ingress and gateway logs, body-size/time limits and network policy. One archive includes tar overhead. Confirm gateway-to-receiver access on port 7777 and API server reachability if policies are enabled.
- Status shows an error: inspect `shadok status` and the daemon's state directory logs. Verify source paths, root mount names and exclusions. `publish` or `build` recreates a compiled snapshot after a successful build; saved jobs and snapshots resume after a daemon restart. Re-run the producer if its retained state was removed or its snapshot is missing.
- ACK but stale app: ACK proves file application to the resolved ready receiver cohort, not framework reload. Check runtime command, classpath, reload configuration and readiness. Verify application HTTP output, and browser HMR separately.
- Restore conflict: external changes to the live PodTemplate or a replaced Deployment UID are deliberately refused. Stop the conflicting GitOps/application update and inspect the live template plus the session-owned baseline ConfigMap. Preserve evidence and resolve the actual change deliberately; do not blindly overwrite either template. Crash recovery records a pending template before applying it, but non-deterministic admission changes can still require diagnosis.
- Skill drift: `shadok agent status` reports modifications. The installer refuses to overwrite modified/foreign content. Keep local instructions elsewhere, preserve those edits and choose a new --path or deliberately move the old directory before reinstalling. No hooks or MCP registrations are created by the skill installer.

## Current limits

Linux and macOS CLI on amd64/arm64. Local Unix-socket daemon; no Windows binary. Polling hashes source trees once per second. Up to 20,000 files, 64 MiB per file, 512 MiB per revision, eight groups per daemon. Symbolic links and special files are refused. Updates are atomic per file, not across a whole revision; file/directory transitions at the same path are unsupported. There is no distributed writer lease: dedicate a live target to one developer. Delivery is retried when receiver cohorts change, but simultaneous independent producers are not coordinated. Authentication remains a platform responsibility. Report rendering, TCP tests, receiver ACK and real application behavior as distinct evidence.

## Spring production/live walkthrough

Run `shadok learn spring` (or `shadok docs spring`) for the complete production-to-DevTools procedure, including a platform-prepared read-only DevTools volume with no image override, the separate-live-image alternative, build publication, class additions/deletions and production restoration.
