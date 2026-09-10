# Go operator and chart review

Scope: operator, gateway, daemon, CRD, packaging, documentation and tests. Spring and Quarkus remain application examples; the Go operator has no language-specific runtime dispatch.

## Verified corrections

- Deployment patches use resourceVersion-based optimistic locking, preventing silent overwrites of concurrent updates.
- The expected template is persisted before application, after server dry-run/defaulting. Recovery accepts the applied or pending template. Tests inject a failure after the Deployment patch and verify restoration. Non-deterministic admission can still require explicit recovery if dry-run and actual results differ.
- A Deployment still marked live without its baseline is reported as an error, not falsely declared restored.
- Inactive sessions do not acquire finalizers. A finalizer is removed after successful restoration. The uninstall hook refuses enabled sessions or pending restoration.
- Session labels and baseline names use UIDs to respect Kubernetes name/label limits even for long resource names.
- Network I/O no longer holds the daemon job mutex. Status/unwatch remain responsive during blocked delivery. Cancellation keeps an in-flight snapshot readable until its reader exits, then reclaims it; race tests cover the scenario.
- The optional live image applies to both application and seed containers. Restoration preserves the original image/pull policy. Compiler and runtime bases are configurable when building Shadok images.
- Operator and gateway have separate service accounts. Gateway access is read-only, without Secrets or exec permissions. Namespace scopes constrain both the controller cache and the gateway resolver before Kubernetes access.
- Controllers support leader election. The separate gateway supports optional HPA, while both components expose scheduling, probes, resources and PDB settings.
- Gateway buffering distinguishes server storage failures from oversized uploads.

## Remaining constraints

The API is alpha. Built-in authentication and distributed writer arbitration are absent. Updates are atomic per file, not across the entire directory tree; file/directory type transitions remain limited. Application commands must implement reload. Changed Vite source is not evidence of browser HMR.

External Pod-template changes cause a conflict and require explicit resolution. Do not delete baselines or force-remove finalizers to conceal such conflicts. Avoid overlapping independently elected operator installations.

HPA, ServiceMonitor and NetworkPolicy objects require metrics-server, Prometheus Operator and an enforcing CNI respectively. Template rendering is not evidence that these integrations work on every target platform.

Code Moniker 0.11.0 had no applicable Go architecture checks for this module during the initial review. Evidence therefore comes from code inspection, Go tests, Helm rendering and Kubernetes integration, not a fabricated architecture score.

See [validation](VALIDATION.md) for executed checks and [release readiness](RELEASE_READINESS.md) for publication requirements.
