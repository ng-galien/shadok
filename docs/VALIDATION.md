# Run the validation suite

Run commands from the repository root. Integration tests use the dedicated `shadok-go-e2e` Kind cluster and `/tmp/shadok-go-e2e.kubeconfig`; install the test infrastructure and load the sample images first.

## Code, chart and daemon

```sh
make -C operator-go generate verify local-e2e
```

## Application synchronization

```sh
python3 operator-go/test/e2e/kind_e2e.py --stack spring
```

Available stacks: `baseline`, `node`, `python`, `spring`, `ts`, `vite`. Run them sequentially. Check application responses as well as transfer acknowledgements. The Vite test checks served source, not browser HMR.

## Lifecycle and network

```sh
python3 operator-go/test/e2e/chart_lifecycle.py
python3 operator-go/test/e2e/finalizer_lifecycle.py
```

The finalizer test deletes the CRD in the dedicated cluster. Other sessions must be inactive; the test saves and restores them.

Follow the [local ingress procedure](LOCAL_INGRESS.md) for HTTPS routing, transfer limits and destination isolation.

## Focused procedures

- [Spring Boot layers and reload](SPRING_LAYERED_IMAGE_VALIDATION.md)
- [Quarkus fast-jar and framework-only reload resources](QUARKUS_LIVE_VALIDATION.md)
- [Session and CRD deletion](SESSION_DELETION_VALIDATION.md)
- [CLI and cluster updates](UPGRADE_VALIDATION.md)
- [Release checks](RELEASE_READINESS.md)
- [Installing published artifacts](INSTALL_RELEASE.md)

After each integration run, check application restoration and stop test daemons. Record the tested revision, Kubernetes version and image digests with test results.
