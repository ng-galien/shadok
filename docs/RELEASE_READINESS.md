# Release readiness

Branch pushes prepare reviewable local artifacts only. The tag-only release workflow publishes GitHub release assets and GHCR images/chart after its identity guard and full verification succeed. No tag or release is created by a branch push. A successful local run is separate from a successful GitHub Actions run and from public availability.

The tag reuses a successful `verify.yml` push run on `main` only for the exact tagged commit in this repository. Without that evidence, it runs the full verification workflow. An API lookup failure also falls back to full verification.

Go module and compilation caches are refreshed per commit with dependency-key fallback. Kind images package the static Linux binaries already built by `make verify`; they do not compile them again. Release image builds share a persistent BuildKit cache, rotated only after successful export. Cache misses affect speed, never whether checks run.

## Automated verification

The verification workflow runs on pushes, pull requests and manual dispatch with read-only repository permissions. It pins action revisions and the Ubuntu runner family, verifies the downloaded Helm checksum, and checks:

- Go formatting, regenerated CRD and deep-copy consistency, race tests, build and vet;
- Helm strict lint and chart unit tests, including invalid values and rendering variants;
- local daemon integration;
- release argument validation, deterministic CLI archive metadata, all four target platforms, image substitution and checksums;
- a real native packaged CLI version and release checksums;
- isolated Kind chart installation, Helm connection test, HA upgrade, rollback and protected uninstall;
- baseline Deployment synchronization and restoration through the gateway.

Unpublished CLI/chart bundles are retained as workflow artifacts for seven days. Failed Kubernetes runs retain diagnostics. These artifacts are review outputs, not a release channel. The workflow does not exercise every demo language, every Kubernetes distribution, enforced NetworkPolicy, or every ingress controller. Full ingress and demo integration procedures remain in the validation documentation.

## Artifact contract

`operator-go/scripts/package.py` produces macOS and Linux CLI archives for AMD64 and ARM64, a versioned chart, an explicit unpublished release manifest, and SHA-256 checksums covering the archives, chart and manifest. The chart uses the explicitly supplied image prefix and release version. CLI archives contain the executable and MIT LICENSE, with fixed ownership, modes and timestamps. The chart carries an identical copy of the canonical root LICENSE, verified by tests and embedded in chart export; container images include it at /usr/share/licenses/shadok/LICENSE. Go builds omit local source paths and VCS stamping. This does not claim that Helm chart archives or images are byte-for-byte reproducible across different tools or base images.

`operator-go/scripts/images.py` defaults to local multi-platform OCI archives. Publishing requires its explicit `--push` option and registry credentials supplied by the operator. It records Buildx metadata, base image references, platform list and checksums. Pin both custom build and runtime bases by digest for repeatable release inputs; defaults are moving tags. OCI-compatible semantic versions are required; leading `v`, leading-zero numeric identifiers and `+` build metadata are rejected.

The Python release tests are offline contract tests with mocked build commands. They complement actual compilation and packaging in CI; they do not prove a registry push or multi-platform container startup.

## Publication requirements

1. **License:** Shadok is MIT licensed; see root `LICENSE`. Dependency and base-image notices retain their own terms.
2. **Release destinations:** the tag workflow targets GitHub releases in `ng-galien/shadok`, images under `ghcr.io/ng-galien/shadok/{operator,gateway,tools}`, and the chart at `oci://ghcr.io/ng-galien/shadok/charts/shadok`. Verify package access and visibility.
3. **Release identity:** keep root `VERSION`, chart metadata and the release tag `v<VERSION>` aligned. Create the tag after branch CI passes.
4. **Access model:** the synchronization endpoint currently relies on a trusted network. Built-in writer authentication is not available. Document that deployment boundary in the public release; do not describe the gateway as safe for unrestricted Internet exposure.

Follow [the distribution procedure](DISTRIBUTION.md), verify checksums and image digests at the destination, and install the downloaded chart with the downloaded CLI against a disposable supported cluster. Record the tested Kubernetes version, platforms and image digests in the release notes.
