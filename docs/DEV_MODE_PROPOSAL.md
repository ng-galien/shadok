# Architecture: live mode on an existing Deployment

The platform owns the Deployment and its baseline image. Shadok owns a `DevelopmentSession` referencing that Deployment in the same namespace. The operator saves the Pod template, transforms it for a live session, and restores it on disable or deletion. Existing Services retain their selectors.

The CRD describes generic container, directory and start-command configuration. It does not contain language, framework or package-manager catalogs. An injected static seed binary copies image directories into temporary volumes without requiring a shell. Reload tooling is provided by the application image or a platform-mounted volume. File transport does not infer compilation or commands from extensions.

The Go daemon is started or reused by the CLI and build hooks. It observes selected source directories or retains a snapshot captured after a successful compilation. It talks HTTP(S) to `/<namespace>/<deployment>` without Kubernetes credentials or port forwarding. The gateway and operator have separate Kubernetes permissions; the developer only needs to change the session CR to enable or disable live mode.

Namespace and target routing are not user authentication. The daemon does not retrieve Secrets or require a token; protect the gateway at the network/proxy boundary.

The chart installs the CRD and infrastructure, with an optional session instance configured through values. Additional releases may create only session instances. CRD upgrades remain a platform responsibility. The operator supports leader election and scoped namespaces; avoid overlapping independent installations.

Cleanup preserves external template edits while reverting Shadok changes. Synchronization uses periodic scans and per-file atomicity; it has no distributed writer lease. Verify application reload separately from file transfer. Operational instructions are available in `shadok learn`.
