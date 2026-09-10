# Changelog

## 1.0.0 — prepared, not yet released

- Replace the former Java operator with a Go operator for generic existing Deployments. Preserve Java demo applications.
- Add the Shadok CLI, local synchronization daemon and gateway, with source watching and successful-build publication hooks.
- Package a configurable Helm chart with schema validation, chart unit tests and installation, upgrade, rollback and restoration checks.
- Embed operational documentation and chart export in the CLI. Provide a minimal model-independent skill that routes agents to `shadok learn`.
- Add local release packaging for macOS/Linux on AMD64/ARM64, container build-base overrides, checksums and tag-only publication with source-version and main-branch ancestry checks.
- License Shadok under MIT.

The Kubernetes API remains `v1alpha1`. The gateway requires a trusted network or platform access control; it does not provide built-in writer authentication. See `docs/VALIDATION.md` for tested behavior and limits.
