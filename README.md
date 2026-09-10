# Shadok

Shadok enables live development on an **existing Kubernetes Deployment**. The Go operator saves its original Pod template, injects temporary directories and a synchronization receiver, and restores the template when the session ends. Existing Services and routing remain usable.

`DevelopmentSession` describes a container, directories, a start command, and an optional development image. Runtime and framework behavior belongs to the application image, not an operator language catalog. The CLI and daemon send files over HTTP(S) through the gateway; builds remain local and failed builds are not published. The daemon requires no Kubernetes credentials.

## Start with the binary

```sh
shadok --help
shadok learn
shadok docs install
```

Operational guidance is embedded in the executable. It covers cluster installation, configuration, source watching, successful-build hooks, verification, troubleshooting and restoration. Use `shadok chart export ./shadok-chart` to materialize the bundled chart without a source checkout. Registry images must be explicitly selected from a release you trust; documentation does not assume an unpublished public registry exists.

## Develop and verify

Requires Go 1.26+, Helm and Docker. Kind and kubectl are needed for Kubernetes integration tests.

```sh
make -C operator-go generate verify
make -C operator-go chart-test
make -C operator-go local-e2e
make -C operator-go generic-images
./scripts/cluster-up.sh
./scripts/deploy-operator.sh
```

The local scripts explicitly target `shadok-go-e2e`; they preserve an existing cluster and do not install demo applications implicitly.

## Repository guides

- [CLI and operator overview](operator-go/README.md)
- [Helm chart configuration and lifecycle](operator-go/chart/README.md)
- [Packaging and distribution](docs/DISTRIBUTION.md)
- [Operator review](docs/OPERATOR_REVIEW.md)
- [Validation evidence](docs/VALIDATION.md)
- [Local HTTPS ingress integration](docs/LOCAL_INGRESS.md)
- [Daemon and build contract](docs/DAEMON_BUILD_CONTRACT.md)
- [Application examples](pods/README.md)

The API is `v1alpha1`. Protect the gateway through a trusted network or an authenticated ingress; built-in writer authentication is not implemented. File synchronization acknowledgements and application reload verification are separate checks. Local validation does not imply a published release.

Shadok is licensed under the [MIT License](LICENSE).
