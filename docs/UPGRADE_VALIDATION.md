# Verify an upgrade

## CLI download

Install a published version into a disposable path:

```sh
shadok upgrade cli --version "$SHADOK_VERSION" --output /tmp/shadok-upgrade-check
/tmp/shadok-upgrade-check version
```

Set `SHADOK_VERSION` to the release under test. Check that checksum verification succeeds and the installed binary reports that version.

## Cluster update

Use a dedicated test cluster and an existing Helm release:

```sh
shadok upgrade cluster --context kind-shadok-go-e2e \
  --namespace shadok-live-system --release runtime --dry-run

shadok upgrade cluster --context kind-shadok-go-e2e \
  --namespace shadok-live-system --release runtime \
  --backup-dir ./upgrade-test-backup
```

Add `--values FILE` when testing custom images.

Check:

- Dry run changes no cluster resources.
- The backup contains previous values/manifests and the proposed configuration.
- Operational values are preserved; selected image versions are updated.
- Operator and gateway rollouts complete.
- A build/sync changes the application response.
- Disabling the session restores production.

Run CLI tests with `go test ./cmd/shadok` from `operator-go` for checksum rejection, dry-run behavior and saved-value handling.
