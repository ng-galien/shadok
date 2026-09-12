# Build and synchronization command reference

The complete runtime guides (`spring`, `quarkus`, `node`, `python`) provide their own configuration and commands. Use this reference to integrate an already working command into your build tool or CI.

## 1. Run a build and publish only its successful output

```sh
shadok build --config shadok.yaml --group service \
  --url "$SYNC_URL" --namespace "$NAMESPACE" --deployment "$DEPLOYMENT" \
  -- YOUR_BUILD_COMMAND YOUR_BUILD_ARGUMENTS
```

Arguments before `--` belong to Shadok. The command after `--` runs in the current directory. Shadok starts or reuses its daemon, executes the build, snapshots the configured output roots after success and waits for a file-application acknowledgement. A failed build publishes nothing.

Use the build command established by the runtime guide; an arbitrary `mvn verify` does not create a Quarkus staging directory. There is no implicit Maven profile, Gradle plugin or generated npm script.

## 2. Publish from an existing successful-build hook

```sh
shadok publish --config shadok.yaml --group service \
  --url "$SYNC_URL" --namespace "$NAMESPACE" --deployment "$DEPLOYMENT"
```

Run only after the build and any required staging step succeed. The hook must prevent concurrent writes to its output directories while they are captured. Do not combine the hook with `shadok build` around the same build: that would publish twice.

## 3. Watch directly executable source files

```sh
shadok watch --config shadok.yaml --group source \
  --url "$SYNC_URL" --namespace "$NAMESPACE" --deployment "$DEPLOYMENT"
```

The group must use `mode: watch`. The application must already run the appropriate reload server. Do not watch compiler output while compilation is writing a partially updated set; use a successful-build boundary.

## 4. CI environment

Install the CLI on PATH. Supply the gateway origin, application namespace/Deployment and optional `--ca-file` for private TLS. The daemon does not need Kubernetes credentials. Keep builds for one output directory serialized.

A persistent daemon retains the latest snapshot and can resend after pod replacement. An ephemeral CI job must publish again when its daemon/state have gone away. File delivery does not prove application reload: make an HTTP assertion against the application URL.

## 5. Inspect or stop synchronization

```sh
shadok status
shadok unwatch --config shadok.yaml --group service \
  --url "$SYNC_URL" --namespace "$NAMESPACE" --deployment "$DEPLOYMENT"
```

`unwatch` removes this synchronization job; it does not disable the DevelopmentSession. Restore production using the runtime guide's final chapter. `shadok daemon stop` stops all jobs of the local daemon, so use it only when that is intended.
