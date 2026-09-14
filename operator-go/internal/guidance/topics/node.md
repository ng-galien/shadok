# Put an existing Node.js application into live mode

## 1. Prerequisites and target values

Work in the application's repository. The platform supplies an installed Shadok gateway, the existing Deployment/container details and access to DevelopmentSessions. Keep the application's chart, routing and production image.

```sh
export CONTEXT=YOUR_CONTEXT
export NAMESPACE=YOUR_APPLICATION_NAMESPACE
export DEPLOYMENT=YOUR_EXISTING_DEPLOYMENT
export IMAGE=YOUR_IMMUTABLE_PRODUCTION_IMAGE
export SYNC_URL=https://YOUR_SYNC_GATEWAY
export SYNC_CA="" # Set an absolute PEM CA path only for a private gateway CA.
export APP_URL=https://YOUR_APPLICATION_HOST
```

Create `live/session.yaml` using this guide. No Shadok npm package or script is assumed.

## 2. Inspect the application and choose what to synchronize

Read `package.json`, the lockfile, build scripts and image configuration. Obtain the rendered Deployment from the platform; with permission:

```sh
kubectl --context "$CONTEXT" -n "$NAMESPACE" get deployment "$DEPLOYMENT" -o yaml
docker pull "$IMAGE"
docker image inspect "$IMAGE"
mkdir -p live/inspect
CONTAINER_ID=$(docker create "$IMAGE")
# Replace /app with the real working directory from the image.
docker cp "$CONTAINER_ID:/app/package.json" live/inspect/package.json
docker rm "$CONTAINER_ID"
```

Record the actual entry file, Node version, user/group, working directory, dependency directory, application port and readiness endpoint. Keep required `NODE_OPTIONS`, environment and arguments. Do not assume a production image contains npm, TypeScript, nodemon or Vite.

| Actual runtime | Local files to send | Live process |
| --- | --- | --- |
| Node runs compiled JS, including TypeScript output | Complete build directory such as `dist` | Node's supported `--watch` mode, or the project's supplied supervisor |
| Node runs JavaScript sources | The source directory used by the entry file | Node `--watch` or an installed source watcher |
| Static files served by nginx or another web server | Built assets | Existing web server; browser refresh, not Node HMR |
| Vite development server requested | Sources plus project configuration and development dependencies | Requires an actual Node/Vite environment; see chapter 7 |

Check `node --help` for `--watch` in the image without starting the application:

```sh
docker run --rm --entrypoint node "$IMAGE" --help
```

Node watch mode follows the entry file and loaded modules. It does not promise discovery of arbitrary unimported files. The Linux pod cannot use Node's macOS/Windows-only `--watch-path`. If this does not fit the application's module loading, use its verified watcher rather than assuming all file changes reload.

## 3. Write the live session

This complete YAML is for an application running `/app/dist/server.js`. Replace those paths, IDs, container and workload names using chapter 2. The image must already contain Node with watch support and the application's runtime dependencies.

`live/session.yaml`:

```yaml
apiVersion: shadok.org/v1alpha1
kind: DevelopmentSession
metadata:
  name: node-live
  namespace: APPLICATION_NAMESPACE
spec:
  enabled: false
  deployment: EXISTING_DEPLOYMENT
  container: APPLICATION_CONTAINER
  runAsUser: 1000
  runAsGroup: 1000
  directories:
    - name: application
      imagePath: /app/dist
      mountPath: /app/dist
      localPath: dist
  start:
    command: [node]
    args: [--watch, dist/server.js]
    workingDir: /app
```

Shadok initializes the writable directory with the image's existing files. `node_modules` and `package.json` stay in the image, outside the mirror, so module resolution retains its original paths. Do not mount the whole `/app` just to update `dist`.

For source JS, replace both directory paths with the actual source path, and the entry argument with its real relative path, such as `src/server.js`. For a static web server, retain its actual production command/arguments and mirror only its served assets directory.


### Optional live probes and resources

Add this under `spec` in the same session, replacing `APPLICATION_CONTAINER` with the existing container name. The values are examples to size for your application:

```yaml
  podTemplatePatch: |
    spec:
      containers:
        - name: APPLICATION_CONTAINER
          livenessProbe: null
          resources:
            requests:
              cpu: "500m"
            limits:
              cpu: "2"
```

This example disables liveness during live mode and changes CPU only. Readiness and memory remain inherited. Use the same Kubernetes fields to adjust probes instead of removing them. A startup probe protects initial startup, not subsequent reloads.

Keep the `|`: the patch is YAML text, so `null` deletions survive Helm and `kubectl apply`. The patch uses Kubernetes Strategic Merge Patch rules on the pod template: containers and environment variables merge by name, omitted fields are retained, and `null` removes a field. Lists without a merge strategy are replaced. The operator applies it to the saved production template before adding Shadok's command, mounts and synchronization containers; those session-managed settings take precedence. Deployment selectors and replicas are outside this patch.

Apply changes to the session to trigger a new rollout. Removing a patch field restores that production value; disabling the session restores the production template. No manual Deployment patch is required.

## 4. Write the local mapping and build command

Set `localPath: dist` on the session's application directory for compiled output, or `localPath: src` for executable source. Use the project's actual output directory relative to the CLI working directory. Shadok reads it from the session. Ensure the build removes obsolete output files after source deletion.

After activation in chapter 5:

```sh
shadok build --session "$NAMESPACE/node-live" \
  --url "$SYNC_URL" --ca-file "$SYNC_CA" \
  -- npm run build
```

`npm run build` must already be defined by this project. Shadok executes it, then publishes only on success. Replace it with the actual pnpm/yarn/build command if appropriate. For a private gateway CA, set `SYNC_CA` to its absolute PEM file path; otherwise leave it empty.

For source JS, set the session directory's `localPath` to `src`.

Start synchronization after activation:

```sh
shadok watch --session "$NAMESPACE/node-live" \
  --url "$SYNC_URL" --ca-file "$SYNC_CA"
```

Dependency/lockfile changes require corresponding runtime dependencies before activation. Do not copy macOS native `node_modules` into a Linux pod or assume syncing source installs packages.

## 5. Activate and verify actual reload

```sh
kubectl --context "$CONTEXT" apply -f live/session.yaml
kubectl --context "$CONTEXT" -n "$NAMESPACE" patch developmentsession node-live \
  --type merge -p '{"spec":{"enabled":true}}'
kubectl --context "$CONTEXT" -n "$NAMESPACE" get developmentsession node-live -o yaml
curl -i "$APP_URL/YOUR_EXISTING_ENDPOINT"
```

Wait for `Ready=True` for the current generation and an application response. Run the selected synchronization command. Change an existing response, add a route through the application's real router/imports, then remove it and its import. Build/publish each compiled change, or let the source watcher send it. Verify the route returns 404 → 200 → 404 and the unchanged route still works.

With pod read rights, capture this before and after the updates using the Deployment's actual selector:

```sh
kubectl --context "$CONTEXT" -n "$NAMESPACE" get pods -l app=YOUR_APP_LABEL \
  -o jsonpath='{range .items[*]}{.metadata.uid}{" "}{range .status.containerStatuses[*]}{.name}{" "}{.containerID}{" "}{.restartCount}{"\n"}{end}{end}'
```

The application child process can restart under Node's watcher while Pod/container identity remains unchanged. Ask the platform for this identity/log comparison when you have only session rights. An ACK proves file delivery, not reload. Static assets require an actual browser refresh and cache check.

## 6. Restore production

Run from the same project directory as publication/watch, with the same `SYNC_URL` and `SYNC_CA`. These values identify the local synchronization job.

```sh
shadok unwatch --session "$NAMESPACE/node-live" \
  --url "$SYNC_URL" --ca-file "$SYNC_CA"
kubectl --context "$CONTEXT" -n "$NAMESPACE" patch developmentsession node-live \
  --type merge -p '{"spec":{"enabled":false}}'
kubectl --context "$CONTEXT" -n "$NAMESPACE" get developmentsession node-live -o yaml
curl -i "$APP_URL/YOUR_EXISTING_ENDPOINT"
```

Check `Ready=True`, reason `Baseline`, for the current generation and the original application's response.

## 7. Vite: distinguish built assets from a development server

If the production image is nginx plus built assets, chapter 3's static-assets route can update that site, but it cannot run Vite: Node, Vite and the source project are absent. For browser HMR the platform must provide a compatible Node/Vite runtime and source/configuration, through an explicitly selected live image or prepared tooling. Do not label static asset delivery as HMR.

For an image that already contains the project's compatible Node, Vite, lockfile dependencies, index.html and Vite config, use the following `start` in chapter 3's session and map the actual source directory:

```yaml
start:
  command: [./node_modules/.bin/vite]
  args: [--host, 0.0.0.0, --port, '8080', --strictPort]
  workingDir: /app
```

Replace 8080 with the application's Service/probe port. Set the exact application hostname in Vite's `server.allowedHosts` configuration; configure its `server.hmr` host/protocol/clientPort for the application's Ingress and permit WebSocket forwarding. These settings must be present in the configuration used by that live runtime. Use the source mapping and watch command above. Change a rendered component, verify the browser updates over the WebSocket, then delete it cleanly. Fetching the changed source file over HTTP does not establish browser HMR.

References: [Node CLI watch mode](https://nodejs.org/api/cli.html#--watch), [Vite server options](https://vite.dev/config/server-options).
