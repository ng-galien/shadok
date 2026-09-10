# Release readiness

Branch pushes prepare reviewable local artifacts only. The tag-only release workflow publishes GitHub release assets and GHCR images/chart after its identity guard and full verification succeed. No tag or release is created by a branch push. A successful local run is separate from a successful GitHub Actions run and from public availability.

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

## Decisions required before public distribution

1. **License:** Shadok is MIT licensed; see root `LICENSE`. Dependency and base-image notices retain their own terms.
2. **Release destinations:** the tag workflow targets GitHub releases in `ng-galien/shadok`, images under `ghcr.io/ng-galien/shadok/{operator,gateway,tools}`, and the chart at `oci://ghcr.io/ng-galien/shadok/charts/shadok`. Before the first release, verify package access and visibility; configured destinations do not establish public availability.
3. **Release identity:** the selected first version is `1.0.0`, recorded in root `VERSION` and chart metadata. The future tag is `v1.0.0`. Tag creation remains a separate authorized action after branch CI passes.
4. **Access model:** the synchronization endpoint currently relies on a trusted network. Authentication was explicitly deferred. Document that deployment boundary in the public release; do not describe the gateway as safe for unrestricted Internet exposure.

After those decisions, follow [the distribution procedure](DISTRIBUTION.md), verify checksums and image digests at the destination, and install the downloaded chart with the downloaded CLI against a disposable supported cluster. Record the tested Kubernetes version, platforms and image digests in the release notes. No commit, tag, registry push or public release is implied by this readiness review.

## Local review evidence

On 2026-09-10, the offline release contract suite passed (four tests), and actionlint v1.7.7 accepted the workflow. An actual `0.1.0-final-review` bundle using the deliberately non-published `example.invalid/shadok` prefix compiled all four CLI targets and passed strict chart lint. Its five distributable files and release manifest passed checksum verification. The native macOS ARM64 executable passed help, learn, chart export, and minimal skill install/status/uninstall. Its exported chart matched all 19 files and normalized metadata of the packaged chart, with correct versioned references for all three images and no Finder metadata. The installed skill contained only its routing Markdown and ownership manifest. Linux execution remains part of the workflow, not a local claim from cross-compilation alone. GitHub Actions has not yet run this uncommitted revision.

The subsequent 1.0.0 packaging update includes the MIT license in CLI archives, the chart and runtime images; the chart therefore now contains 20 maintained files. The earlier 19-file parity observation above predates that addition.
