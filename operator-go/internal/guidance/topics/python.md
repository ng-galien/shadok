# Put an existing Python application into live mode

## 1. Prerequisites and target values

Work in the application's repository. Keep its existing image, Deployment/chart, configuration and routing. The platform supplies Shadok, its gateway address and permissions to manage DevelopmentSessions.

```sh
export CONTEXT=YOUR_CONTEXT
export NAMESPACE=YOUR_APPLICATION_NAMESPACE
export DEPLOYMENT=YOUR_EXISTING_DEPLOYMENT
export IMAGE=YOUR_IMMUTABLE_PRODUCTION_IMAGE
export SYNC_URL=https://YOUR_SYNC_GATEWAY
export SYNC_CA="" # Set an absolute PEM CA path only for a private gateway CA.
export APP_URL=https://YOUR_APPLICATION_HOST
```

Create `live/session.yaml` using the chapters below. The synchronization client needs gateway access, not Kubernetes credentials.

## 2. Inspect the Python environment

Read the project's lockfile, packaging/build configuration and production start command. Obtain the rendered Deployment from the platform; with read permission:

```sh
kubectl --context "$CONTEXT" -n "$NAMESPACE" get deployment "$DEPLOYMENT" -o yaml
docker pull "$IMAGE"
docker image inspect "$IMAGE"
```

Record the real Python executable (including a virtualenv path if used), application source/package directory, import target, working directory, user/group, port and probes. To inspect without starting the application:

```sh
mkdir -p live/inspect
CONTAINER_ID=$(docker create "$IMAGE")
# Use the actual directory discovered in the image.
docker cp "$CONTAINER_ID:/app" live/inspect/application
docker rm "$CONTAINER_ID"
```

Use the image's Python interpreter to check the selected reload server, without importing the application:

```sh
docker run --rm --entrypoint python "$IMAGE" -m uvicorn --version
```

Replace `python` with the actual interpreter. If Uvicorn is not the application's server, inspect the appropriate installed framework instead. A production image does not necessarily include reload dependencies. The platform must provide missing packages in an environment compatible with the image's Python, OS and architecture; do not copy a workstation virtualenv into the pod.

## 3. Select the live process

| Application | Process to configure |
| --- | --- |
| FastAPI/other ASGI application, Uvicorn installed | `python -m uvicorn PACKAGE.MODULE:APP --reload ...` |
| Django project with manage.py and Django installed | `python manage.py runserver 0.0.0.0:PORT` |
| Flask project with Flask installed | `python -m flask --app IMPORT_TARGET run --reload --no-debugger --host 0.0.0.0 --port PORT` |
| Worker, command-line program or other server | Identify and supply its actual supervisor/reload command; plain Python does not reload automatically |

Preserve required application settings/import paths and bind to the existing Service port. For Uvicorn, use a single reloading process instead of production `--workers`; those options are incompatible. Ensure the installed watcher detects additions and deletions required by your workflow. Uvicorn's basic polling fallback is limited; `watchfiles` provides its fuller file-event support.

## 4. Create the session YAML

This complete configuration is for an ASGI application whose image already contains `/app/src/main.py` and Uvicorn. Replace every application value and path using chapter 2.

`live/session.yaml`:

```yaml
apiVersion: shadok.org/v1alpha1
kind: DevelopmentSession
metadata:
  name: python-live
  namespace: APPLICATION_NAMESPACE
spec:
  enabled: false
  deployment: EXISTING_DEPLOYMENT
  container: APPLICATION_CONTAINER
  runAsUser: 1000
  runAsGroup: 1000
  directories:
    - name: application
      imagePath: /app/src
      mountPath: /app/src
      localPath: src
      exclude: ['**/__pycache__', '**/__pycache__/**', '**/*.pyc']
  start:
    command: [python]
    args: [-m, uvicorn, 'main:app', --app-dir, /app/src, --host, 0.0.0.0, --port, '8000', --reload, --reload-dir, /app/src]
    workingDir: /app
```

The original sources seed the writable directory. The virtualenv and site-packages remain outside the mirror. For an installed application package under site-packages, identify only that application's package directory; never mirror the entire environment. Verify imports resolve to the synchronized directory.

For Django or Flask, replace `start` with the corresponding command from chapter 3, split into executable and argument list, and use its actual project working directory. Keep the image's port/probes aligned with that command. `spec.image` is omitted to retain the production image.


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

## 5. Create the source mapping

Set `localPath` on the session directory to the source directory relative to the CLI working directory. The gateway supplies that mapping and its exclusions to the client. No local YAML is needed. Keep virtual environments and credentials outside the mirrored tree.

For generated source, use `shadok build ... -- YOUR_GENERATION_COMMAND` after activation instead of watching partially generated output.

## 6. Activate and start synchronization

```sh
kubectl --context "$CONTEXT" apply -f live/session.yaml
kubectl --context "$CONTEXT" -n "$NAMESPACE" patch developmentsession python-live \
  --type merge -p '{"spec":{"enabled":true}}'
kubectl --context "$CONTEXT" -n "$NAMESPACE" get developmentsession python-live -o yaml
curl -i "$APP_URL/YOUR_EXISTING_ENDPOINT"
```

Wait for `Ready=True` for the current generation and an application response. Then:

```sh
shadok watch --session "$NAMESPACE/python-live" \
  --url "$SYNC_URL" --ca-file "$SYNC_CA"
shadok status
```

For a private gateway CA, set `SYNC_CA` to its absolute PEM file path; otherwise leave it empty. Use the gateway origin for synchronization and the application's URL for HTTP checks.

## 7. Verify changes, additions and deletions

Change an existing response. Add a route using the application's router/module registration. Then delete the route/module and remove its import. For each step, wait for sync and check the HTTP response:

```sh
curl -i "$APP_URL/YOUR_NEW_ENDPOINT"
```

Expect 404 → 200 → 404, while an unchanged route still responds. If a deletion alone is not detected by the installed watcher, do not mark that scenario validated; select a watcher that supports it. Check logs for the selected framework's reload, rather than treating a transfer ACK as a reload result.

With pod read access, capture this before and after the edits using the real Deployment selector:

```sh
kubectl --context "$CONTEXT" -n "$NAMESPACE" get pods -l app=YOUR_APP_LABEL \
  -o jsonpath='{range .items[*]}{.metadata.uid}{" "}{range .status.containerStatuses[*]}{.name}{" "}{.containerID}{" "}{.restartCount}{"\n"}{end}{end}'
```

Pod UID, application container ID and restart count must remain unchanged. The Python worker can restart under its reloader. With CR-only access, ask the platform for this comparison and the runtime logs.

## 8. Restore production

Run from the same project directory as publication/watch, with the same `SYNC_URL` and `SYNC_CA`. These values identify the local synchronization job.

```sh
shadok unwatch --session "$NAMESPACE/python-live" \
  --url "$SYNC_URL" --ca-file "$SYNC_CA"
kubectl --context "$CONTEXT" -n "$NAMESPACE" patch developmentsession python-live \
  --type merge -p '{"spec":{"enabled":false}}'
kubectl --context "$CONTEXT" -n "$NAMESPACE" get developmentsession python-live -o yaml
curl -i "$APP_URL/YOUR_EXISTING_ENDPOINT"
```

Check `Ready=True`, reason `Baseline`, for the current generation and the original response. The platform verifies the original production start command is restored.

References: [Uvicorn settings](https://www.uvicorn.org/settings/), [Flask CLI](https://flask.palletsprojects.com/en/stable/cli/), [Django runserver](https://docs.djangoproject.com/en/stable/ref/django-admin/#runserver).
