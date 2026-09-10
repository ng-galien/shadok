# CLI, daemon and build contract

Implementation: `operator-go/cmd/shadok`, `internal/daemon` and `internal/syncer`. Use `shadok learn` for the operational workflow and `shadok docs` to discover embedded reference topics.

1. The project versions groups of named roots, relative paths and exclusions. Each group selects `watch` or `build`. Mount names match the session CR.
2. A personal destination supplies the HTTP(S) origin, namespace and Deployment. It stays outside shared project configuration and contains no Kubernetes credentials.
3. The CLI starts or reuses the daemon through a private Unix socket. A process lock prevents two daemons from sharing one state directory.
4. `watch` captures roots and keeps observing them. `publish` captures completed build outputs once and waits for acknowledgement. `build -- command` captures only after a successful command under the local project lock.
5. The snapshot is immutable. Its revision identifies the manifest, paths, modes, exclusions and SHA-256 hashes. A later compilation does not modify the captured copy.
6. `/plan` compares actual receiver files and requests differences. `/apply` validates uploaded files before replacement and deletion. The gateway combines differences across replicas; acknowledgement covers their receiver cohort.
7. The daemon repeatedly reconciles its latest revision even without local changes. Reconnection, receiver restart and new Pods therefore recover the same files.
8. `unwatch` removes a job; `daemon stop` stops the process. Persisted jobs resume at the next start. `status` reports revision, acknowledgement and the latest error. Network I/O does not hold the job mutex, so status and cancellation remain available during a blocked transfer.

Maven, Gradle and npm hooks use the public CLI, without adding operator dependencies on those tools. Shell `&&` and task dependencies prevent publication after a failed build. Concurrent producers should all use `build` and respect its local lock; arbitrary external writers can still race with capture. There is no distributed publication lease between workstations.

An acknowledgement proves file application, not application reload. Each application's HTTP assertion is separate. Serving changed Vite source does not establish browser HMR, and validating a Quarkus hook does not establish remote Quarkus dev mode.

TLS verification is required, including explicit `caFile` trust for private authorities. There is no certificate-verification bypass. Gateway writer authentication must be supplied by the deployment's trusted network or authenticated proxy.
