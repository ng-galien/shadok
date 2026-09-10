# Shadok CLI and Go operator

This module builds the operator, HTTP gateway, and CLI/daemon/receiver. A `DevelopmentSession` transforms an existing Deployment temporarily and restores its Pod template afterwards. The application supplies its runtime, live command and directory layout.

## Embedded operational guide

The executable is the authoritative entry point for an operating agent:

```sh
shadok --help
shadok learn
shadok docs install
shadok chart export ./shadok-chart
```

Help and documentation work offline without starting the daemon, reading Kubernetes credentials, or requiring this repository. Discover the available topics through `shadok learn`. The embedded guide explains operator installation, project configuration, personal destinations, build hooks, verification, troubleshooting and safe restoration. The exported chart includes its values, schema, CRD and templates.

See the [chart reference](chart/README.md) for its complete configuration surface and [distribution guide](../docs/DISTRIBUTION.md) for release artifacts and custom compiler/runtime bases. Use image repositories and versions that you actually built or obtained; the source chart's local placeholders are not public release coordinates.

## Build and test

Run from this directory with Go 1.26+:

```sh
make generate       # regenerate CRD and deepcopy code
make verify         # race tests, binaries and go vet
make chart-test     # actual Helm render and negative configuration tests
make local-e2e      # daemon and receiver integration
make generic-images # local images; ARCH=amd64 or ARCH=arm64
```

`bin/shadok`, `bin/operator` and `bin/gateway` are separate executables. Maven, Gradle and npm hooks invoke the public `shadok` CLI and must find it on PATH. A failed build must never publish incomplete outputs. The `build` command serializes cooperating local producers before capturing successful output; a process that ignores that lock can still modify the source during capture.

## Contracts

The operator owns the live transformation and restoration. It preserves routing labels, annotations, sidecars, environment, probes and resources, and records the baseline Pod template and Deployment UID. External template changes cause a conflict instead of being overwritten. The session target is immutable. `Ready=True` reports a successful template transition, not completion of the rollout or application reload.

The gateway reads live sessions and ready receiver Pods through its own restricted Kubernetes identity. The developer controls the session CR; the CLI and daemon use only HTTP(S). Source groups are watched periodically. Build groups keep an immutable snapshot until replaced by a later successful build. New receiver cohorts are reconciled even without a local file change.

The optional live application image is used by both the application and seed container; disabling the session restores the original image and pull policy. Shadok's compiler and runtime base images are build-time settings. Private image pull credentials must exist in each namespace where the images are pulled.

Authentication, distributed writer arbitration, whole-tree atomic updates and browser HMR are not implied by the file-transfer protocol. See [review](../docs/OPERATOR_REVIEW.md) and [validation](../docs/VALIDATION.md) for tested behavior and remaining limits.
