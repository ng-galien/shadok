# Validation record

This file distinguishes observed local results from configured CI and publication. No commit, Git push or external artifact publication has been performed by this work. Tests use only the dedicated `kind-shadok-go-e2e` context and `/tmp/shadok-go-e2e.kubeconfig`.

## Operator and chart validation — September 10, 2026

- `make -C operator-go generate verify`: CRD/deepcopy generation, Go race tests, all three binaries and `go vet` passed.
- Chart unit tests executed real Helm rendering for routing, least privilege, namespace scopes, tags/digests, HA, HPA, PDB, ServiceMonitor, NetworkPolicy, metadata, existing accounts, session-only installation, custom live images and invalid values. Strict Helm lint passed.
- Kubernetes 1.36.1 accepted a server dry-run with two replicas, PDB, HPA, metrics, NetworkPolicy, NodePort, Ingress, hooks and custom annotations. This validates objects, not CNI enforcement or Prometheus collection.
- `chart_lifecycle.py`: dedicated namespace installation, `helm test`, HA upgrade, rollback, active-session uninstall rejection with the controller retained, and successful uninstall after disabling the session and removing its finalizer.
- Local daemon integration: automatic add/change/delete, daemon reuse, receiver replacement, immutable completed-build snapshots, failed/successful builds and recovery.
- Kind application integration: two-replica baseline, Node, Python, TypeScript, Vite and Spring passed synchronization, live response, Pod replacement and exact baseline restoration. Vite checks source serving, not browser HMR.
- Real Traefik HTTPS ingress passed in a separate final run: nip.io loopback routing, upload above 2 MiB, delayed request, proxy 413 limit, namespace isolation, CR-only developer identity, application update and exact restoration. All six existing application templates were unchanged.
- Maven `-Pshadok verify` and npm build/publish hooks were exercised earlier with received/acknowledged outputs. The final Spring suite again compiled and published class outputs.
- `./gradlew :pods:quarkus-hello:shadokPublish --dry-run --no-daemon` passed with demo tasks and formatting configuration retained. This proves the Gradle task graph, not remote Quarkus dev mode. Existing Gradle APIs report deprecation warnings for a future Gradle 9 upgrade.
- Source builds succeeded for operator, gateway and tools on Linux ARM64 and AMD64. Custom compiler/runtime bases were exercised; the final runtime label remained present and the gateway ran `--version`.
- Four CLI archives (macOS/Linux × AMD64/ARM64), chart `0.1.0-review.2`, checksums and a release manifest were prepared. Native embedded version, hashes, chart schema and hook contents were checked. The chart's local OCI push/pull preserved identical bytes. Three local image manifest lists each contained ARM64 and AMD64. Test images were `dev` builds, not published `0.1.0` release images.
- `git diff --check`, Python syntax checks and CI YAML syntax checks passed. Remote verification subsequently passed on main; see the current publication status below.

## Validation incidents and bounds

Docker disk exhaustion prevented gateway upload buffering. Only the temporary task builder and explicitly identified Shadok build caches were removed; no global prune was performed. The gateway now reports storage errors separately from request size errors. Simultaneous multiarchitecture export was interrupted; separate architecture builds and local manifest assembly succeeded.

An ingress test launched alongside the Node suite correctly failed its unchanged-fixture assertion. The final isolated ingress run passed. A Spring publication timeout was followed by a separate successful full run. Integration cleanup now restores the fixture even when synchronization assertions fail.

The API remains alpha. Authentication, distributed writer leases, whole-tree transactions and native filesystem watching are not implemented. A file ACK is separate from application reload. Non-deterministic admission and external template changes require conservative conflict handling. The complete 544 MiB ingress limit, a 120-second upload, CNI policy enforcement and browser HMR were not tested.

## Evidence and retained state

Temporary local evidence:

- `/tmp/shadok-final-verify.log`
- `/tmp/shadok-chart-server-dryrun.log`
- `/tmp/shadok-chart-lifecycle.log`
- `/tmp/shadok-review-kind.log`
- `/tmp/shadok-review-stacks.log`
- `/tmp/shadok-review-spring.log`
- `/tmp/shadok-review-ingress-final.log`
- `/tmp/shadok-ingress-local/evidence.json`
- `/tmp/shadok-manifest-review.log`
- `/tmp/shadok-release-review/`

Completed test sessions are disabled, report Baseline and have no remaining finalizers. Application Deployments are restored. The `chart-review` release is uninstalled. The `runtime` release, ingress controller and application fixtures remain. The loopback-only test registry container `shadok-release-registry-review` is stopped and retained. Test daemons are stopped.

Subsequent CLI guidance and release-readiness checks are documented in [RELEASE_READINESS.md](RELEASE_READINESS.md); do not treat this earlier validation as proof for later changes until their corresponding checks run.

## Embedded guidance and release preparation follow-up

The final `make -C operator-go verify local-e2e` passed after the minimal skill and explicit chart embedding changes: Go race tests, builds, vet, four release contract tests and daemon synchronization/restart recovery. The Node and Python demos each passed six tests after the English documentation and message cleanup. The skill validator passed; `SKILL.md` only activates for Shadok and routes to `shadok learn`.

The final local bundle in `/tmp/shadok-release-final` compiled all four CLI targets and passed all six checksums, strict chart lint, native offline guidance, chart export and minimal skill install/status/uninstall checks. The exported chart matches all 19 packaged files, including release image references. These historical results predate the final packaging. MIT, GHCR destinations and version 1.0.0 are now selected; see the current publication status below.

## Current publication status

Remote verification passed on commits `9333972` and `fa04d9c`, including real Kind chart lifecycle and baseline synchronization/restoration. Version 1.0.0 is published and the fresh Kind test using anonymous GitHub/GHCR downloads passed. See the [release consumer report](releases/1.0.0-validation.md) and [installation guide](INSTALL_RELEASE.md).

## Sample tooling isolation

The Gradle build/wrapper/catalog now belong to `pods/quarkus-hello`; the obsolete root multi-project launcher was removed. Node, Python and Quarkus own local `shadok.yaml` files. Resolved roots, mount names, modes and exclusions were compared with the previous root configuration and are unchanged. Node's six tests and Quarkus's two tests passed; Quarkus was built using its own wrapper on Gradle 8.14.3 and JDK 21. The standalone `shadokPublish --dry-run` includes compilation and tests before publication. No remote sync was triggered by that dry-run. Earlier root Gradle commands above describe historical validation only.

## Spring production baseline and live class changes

[Live evidence](SPRING_LIVE_VALIDATION.md) verifies a production image without DevTools, activation with an explicitly configured live image, added controller method, added/deleted controller class, stable pod/container identity during reload, and exact production restoration.

[Same-image DevTools volume evidence](SPRING_VOLUME_VALIDATION.md) additionally verifies live reload with the unchanged production image and a platform-provided read-only PVC.
