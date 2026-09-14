# Inspect the target before writing live configuration

Run from the application's repository. Use supplied platform manifests if Deployment read access is unavailable.

## 1. Record the target

Record these values in a local working note:

| Value | Where to obtain it |
| --- | --- |
| Context, namespace, Deployment, container | Platform configuration or deployed manifest |
| Image reference/digest | Deployed container, not a guessed development tag |
| Startup command, args, working directory | Deployment overrides plus image Entrypoint/Cmd/WorkingDir |
| Runtime version and UID/GID | Image metadata, build configuration and runtime inspection |
| Application files and dependency paths | Dockerfile/final image filesystem |
| Build command and output directories | pom.xml, Gradle, package.json, pyproject.toml and a completed build |
| Application port, probes, test URL | Existing Deployment/Service and application config |
| Volumes and read-only filesystem setting | Existing Deployment/container security context |
| Gateway URL and CA | Platform-provided sync endpoint |

If authorized to read the Deployment:

```sh
kubectl --context "$CONTEXT" -n "$NAMESPACE" get deployment "$DEPLOYMENT" -o json > deployment-before.json
```

Keep that snapshot local; it may include environment configuration. Do not edit the image, command or volumes until this inventory is complete.

## 2. Inspect the image without launching the application

Read the Dockerfile and build settings first. If Docker/image access is available:

```sh
docker pull "$IMAGE"
docker image inspect "$IMAGE" > image-inspect.json
CONTAINER_ID=$(docker create "$IMAGE")
# Set APP_PATH from the Dockerfile/image layout:
docker cp "$CONTAINER_ID:$APP_PATH" ./image-application
# If the layout is unknown, list paths without starting the container:
docker export "$CONTAINER_ID" | tar -tf - > image-paths.txt
docker rm "$CONTAINER_ID"
```

A missing shell, npm, Maven, `jar` or `unzip` is normal in a production image. Do not assume they exist. Do not run the application entrypoint just to inspect an archive.

## 3. Choose what to synchronize

| Deployed application | Synchronize | Runtime guide |
| --- | --- | --- |
| Spring JVM JAR | Compiled classes and application resources | `shadok learn spring` |
| Node running JavaScript output | Matching built JavaScript directory | `shadok learn node` |
| Node running source | Source directory, if its reload command supports it | `shadok learn node` |
| TypeScript | JavaScript build output unless a TS runtime is verified in the image | `shadok learn node` |
| Python | Importable source package used by the running server | `shadok learn python` |
| Static frontend image | Built static assets; use Vite only if its runtime/tools are supplied | `shadok learn node` |
| Native binary | Do not apply a JVM/source reload recipe; establish an executable replacement/restart workflow |

Never synchronize a whole application directory if that would delete image-owned dependencies, certificates, configuration or startup scripts. Use dedicated roots for replaceable files.

## 4. Check prerequisites before activation

- Runtime tools exist at the exact paths used by the live command.
- Declare additional tool files with HTTPS URLs and SHA256 checksums in `spec.volumes[].files`: the operator downloads and mounts them before startup. For an existing platform volume, declare its source in `spec.volumes`. Other missing runtime dependencies need an explicitly prepared compatible environment.
- Session UID/GID match the application. A PVC needs the existing compatible fsGroup.
- Live mount paths do not overlap existing mounts.
- The live command keeps the application's bind address, port and required JVM/runtime flags.
- Your image has no unsupported hostNetwork/hostPID/hostIPC/hostPort configuration for this live transformation.

If something is unavailable, identify the exact missing executable, artifact, path or platform change. Do not invent a runtime command or silently rebuild a different application.
