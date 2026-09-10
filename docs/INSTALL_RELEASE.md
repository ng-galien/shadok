# Install a published Shadok release

This is the consumer path: no Go compiler or Shadok source build is required. Use an actually published version from [GitHub Releases](https://github.com/ng-galien/shadok/releases). Version 1.0.0 is published; its [fresh Kind consumer test passed](releases/1.0.0-validation.md).

## Download the CLI

Download `shadok_1.0.0_darwin_arm64.tar.gz` for Apple Silicon, `darwin_amd64` for Intel macOS, or `linux_amd64` / `linux_arm64` for Linux. Windows users need a Linux environment such as WSL. Download `SHA256SUMS-1.0.0`, check the archive's SHA-256 against its line in that file, extract it, and place `shadok` on PATH. The archive includes LICENSE.

```sh
shadok --version
shadok learn
shadok docs install
shadok docs configure
shadok docs builds
```

These guides are embedded and work offline. `shadok chart export ./shadok-chart` exports the same release chart with its versioned image references.

## Install the operator from GHCR

Use Helm 3/4 and Kubernetes 1.34+. The platform administrator installs the CRD and operator; developers only need permissions on DevelopmentSession resources and access to the sync endpoint. On a workstation, Docker and Kind supply an isolated Kubernetes environment:

```sh
kind create cluster --name shadok-professional --kubeconfig ./shadok-kind.kubeconfig
helm pull oci://ghcr.io/ng-galien/shadok/charts/shadok --version 1.0.0
helm upgrade --install shadok oci://ghcr.io/ng-galien/shadok/charts/shadok \
  --version 1.0.0 --kubeconfig ./shadok-kind.kubeconfig \
  --kube-context kind-shadok-professional \
  --namespace shadok-system --create-namespace \
  --values deployment-values.yaml --wait --timeout 5m
helm --kubeconfig ./shadok-kind.kubeconfig test shadok -n shadok-system --logs
```

Prepare `deployment-values.yaml` using the [chart reference](../operator-go/chart/README.md). For an initial private local install it may contain `{}`; this installs the infrastructure with a ClusterIP gateway, not an externally reachable development endpoint. For a usable development environment, configure gateway exposure, namespaces and TLS as below. The OCI chart already references `ghcr.io/ng-galien/shadok/{operator,gateway,tools}:1.0.0`. No `helm repo add` is needed for OCI. Helm can also download/unpack the chart or reference it as a versioned OCI dependency in your platform chart.

Public GHCR packages allow anonymous pulls. For a corporate registry mirror, override all three image repositories; configure imagePullSecrets in each namespace that pulls private images, including application namespaces for the tools image. Your workstation and Kind nodes must be allowed to reach the registries and trust the relevant CA. Registry access and sync endpoint access are separate.

## Connect your application

Keep your existing Helm/Helmfile Deployment. Configure one DevelopmentSession with its container name, image paths, live mounts and live command. The chart's `session.*` values can create it; use `operator.enabled: false` for additional application-only releases. Existing application images must contain the runtime, dependencies and initial directories.

Expose the gateway through your platform's trusted ingress/TLS or private network. Preserve `/<namespace>/<deployment>/plan` and `/apply`. Kind needs host port mappings when using NodePort/Ingress. [The local ingress guide](LOCAL_INGRESS.md) documents the Traefik setup; the release smoke test below uses direct TLS NodePort on loopback. Neither TLS nor nip.io authenticates writers; built-in authentication is not implemented.

Configure the CLI's gateway URL, namespace and Deployment, activate the session, then follow the relevant example:

- [Spring Boot / Maven](../pods/spring-hello/README.md)
- [Quarkus / Gradle](../pods/quarkus-hello/README.md)
- [Node / npm](../pods/node-hello/README.md)
- [Python / FastAPI](../pods/python-hello/README.md)
- [TypeScript](../pods/ts-hello/README.md)
- [Vite](../pods/vite-hello/README.md)

Use `shadok build --config shadok.yaml --group service -- <build command>` on a developer workstation or CI runner. Publication follows success only. Source-driven applications use `shadok watch`. Confirm the application response, then disable the session to restore the baseline. Quarkus remote dev and browser Vite HMR are not established by generic file transfer tests.

## Maintainer: verify the published consumer path

After a release, run from the repository using Python 3.12+, curl, Helm, Docker, Kind and kubectl:

```sh
python3 operator-go/test/e2e/release_smoke.py --version 1.0.0
```

This downloads the CLI without GitHub credentials, verifies checksums, pulls the public chart using empty Helm credentials, creates a fresh `shadok-release-smoke` cluster with loopback port mappings, and installs Shadok from GHCR. It builds only the test application locally. It checks CR-only activation, two replicas, HTTPS synchronization, failed/successful build publication, updates/deletions, pod replacement, exact restoration and Helm connectivity. No port-forward is used. The cluster is retained for inspection; the script refuses to reuse it. Evidence is written under the printed temporary consumer directory. Inspect it before explicitly deleting this disposable cluster and rerunning.
