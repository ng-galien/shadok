# Packaging and distribution

Shadok has four release components: CLI archives, an operator image, a gateway image, and a tools image, plus the Helm chart that references those images. A prepared bundle is not a published release.

## Prepare a local bundle

```sh
make -C operator-go generate verify chart-test
cd operator-go
python3 scripts/package.py --version 1.0.0 --image-prefix registry.example.com/shadok --output dist
```

The script builds CLI archives for macOS/Linux, amd64/arm64, embeds `--version`, packages the chart with the chosen image repositories and matching appVersion, and writes SHA256SUMS and a release manifest (`published: false`). It does not log in or publish. It requires Go and Helm. Review the manifest and hashes before distribution.

## Build container images

```sh
docker buildx create --name shadok-release --driver docker-container
docker buildx build --builder shadok-release --platform linux/amd64,linux/arm64 --target operator \
  --build-arg VERSION=1.0.0 \
  --build-arg BUILD_IMAGE=golang:1.26 \
  --build-arg RUNTIME_IMAGE=gcr.io/distroless/static:nonroot \
  --tag registry.example.com/shadok/operator:1.0.0 \
  --output type=oci,dest=operator-1.0.0.oci.tar .
```

Repeat with targets `gateway` and `tools`, or build all three using:

```sh
python3 scripts/images.py --version 1.0.0 --image-prefix registry.example.com/shadok \
  --builder shadok-release --output dist
```

The script accepts `--build-image`, `--runtime-image`, `--platforms` and an explicit `--push` switch. Without `--push`, it only writes local OCI archives. Custom build/runtime bases may use private registry references or immutable digests. The compilation stage runs on BUILDPLATFORM and cross-compiles for TARGETOS/TARGETARCH. Check base availability for both architectures. For publishing, replace the OCI output with `--push` after registry authorization. Record the resulting image digests and use them in release values. A runtime base change requires a new image build; Helm cannot replace the filesystem layers of an existing image.

## Publish to an OCI registry

After authorization, authenticate using your registry's short-lived credentials and standard input rather than command-line passwords. Push the three versioned images, then the chart:

```sh
helm push dist/shadok-1.0.0.tgz oci://registry.example.com/shadok/charts
helm pull oci://registry.example.com/shadok/charts/shadok --version 1.0.0
helm upgrade --install shadok oci://registry.example.com/shadok/charts/shadok \
  --version 1.0.0 -n shadok-system --create-namespace -f deployment-values.yaml --wait
```

Helm adds the chart name and version to the OCI destination. Archive distribution can instead use `helm repo index` and static HTTPS hosting; OCI keeps image and chart authorization on the same registry. CLI archives and SHA256SUMS can be attached to the release system used by your organization. No public repository, registry or license grant is assumed by these commands.

## Release gates

Run Go race tests/vet, generated CRD checks, chart unit tests/strict lint, local daemon tests and real Kind synchronization tests. Verify installation, `helm test`, upgrade/rollback and guarded uninstall. Test the optional integrations your deployment enables (metrics-server, Prometheus CRD, CNI policy, ingress authentication/TLS). A render pass cannot establish their runtime behavior.

Keep image versions immutable. Add registry-native vulnerability scanning, SBOM/provenance generation and image/chart signing to the organization's release pipeline and verify signatures at consumption. These require the registry/signing identity chosen by the maintainer; this repository's local packaging does not pretend to sign or attest artifacts. Publish only after agreeing on ownership, license and support policy.

Sources: [Helm OCI distribution](https://helm.sh/docs/topics/registries/), [CRD lifecycle limitations](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/).

## Repository release automation

The first selected version is `1.0.0`; root `VERSION` and chart `version`/`appVersion` must agree. Development binaries built directly with `go build` remain marked `dev`; Make builds use `VERSION` unless overridden.

Only a pushed `v*` tag starts `.github/workflows/release.yml`. The guard checks strict semantic versioning, matching source versions, the exact remote tag/event commit and ancestry on the repository's verified default branch `main`. It fetches and checks that identity again before preparing publication. A tag on an unrelated branch is rejected. Branch pushes and pull requests only run verification.

After full verification, the workflow prepares CLI archives and chart, publishes AMD64/ARM64 images under `ghcr.io/ng-galien/shadok`, pushes the chart to `oci://ghcr.io/ng-galien/shadok/charts`, verifies the chart round trip and image platforms, and attaches checksummed artifacts to the GitHub release. A draft release keeps an interrupted publication visibly incomplete; reruns may resume a draft but cannot overwrite a published release. Registry pushes are not transactional, so a failed run may leave images or a chart available before the GitHub release is published.

Shadok uses the root MIT license. Before authorizing the first tag, verify GHCR package visibility/access. Creating or pushing a branch does not create `v1.0.0` or publish any release.
