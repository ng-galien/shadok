# Local HTTPS ingress: Kind, macOS and nip.io

The integration fixture uses Traefik **v3.7.13**, official chart **41.5.0**, and the dedicated non-default ingress class `shadok-local`. It preserves the existing `shadok-go-e2e` cluster and application fixtures.

## Network path

```text
CLI / daemon without kubeconfig
  -> sync.127.0.0.1.nip.io:8443 (DNS resolves to 127.0.0.1)
  -> Docker Desktop port bound only to the Mac loopback interface
  -> opaque TCP relay on the Docker kind network
  -> NodePort 30443 on shadok-go-e2e-control-plane
  -> Traefik TLS termination and Ingress rule
  -> gateway Service / HTTP endpoints on port 8080
  -> /shadok-ingress-e2e/baseline/plan or /apply
  -> live Pod receiver
```

No `kubectl port-forward` is used by this path or its test. The relay does not interpret HTTP or TLS; it connects the Mac to the Kind network without recreating the node. Host ports `127.0.0.1:8080` and `127.0.0.1:8443` forward to NodePorts `30080` and `30443`. Test routes use HTTPS on 8443.

The dedicated gateway serves HTTP without a certificate mount. Traefik presents the test certificate for both nip.io SANs. The daemon verifies it using `--ca-file /tmp/shadok-ingress-local/ca.crt`; no macOS keychain changes or insecure TLS bypass are used. Setup renews the two-day certificate. Public DNS resolves these names to loopback; the URLs are local to this Mac, not remote access links.

## Reproduce

Requires the dedicated cluster, `/tmp/shadok-go-e2e.kubeconfig`, an installed Go operator, and the following images built and loaded into Kind: `shadok-tools:local`, `shadok-operator:local`, `shadok-gateway:local`, `shadok-baseline:local`. The test uses `operator-go/bin/shadok`, Helm, Docker, Python 3 and OpenSSL. Setup downloads the Traefik chart/image as needed.

From the repository root:

```sh
python3 operator-go/test/e2e/ingress/setup.py
python3 operator-go/test/e2e/ingress/test.py
```

Run this test separately from application integration tests: it asserts that the six existing application Deployments remain unchanged. Setup rejects a different cluster, a nip.io name resolving outside loopback, or reconfiguration of an active fixture.

Setup creates only `shadok-ingress-system` for Traefik and `shadok-ingress-e2e` for the gateway, application and session. The session chart uses `operator.enabled: false` to reuse the existing operator. Traefik settings are in `operator-go/test/e2e/ingress/traefik-values.yaml`. The gateway has a namespace-local read-only Role for Pods and sessions. The developer identity can only modify the session CR; the test impersonates that identity for transitions.

- Synchronization: `https://sync.127.0.0.1.nip.io:8443/shadok-ingress-e2e/baseline`
- Application: `https://app.127.0.0.1.nip.io:8443/`

After the test, the session is disabled and the application serves `baseline`:

```sh
curl --cacert /tmp/shadok-ingress-local/ca.crt \
  https://app.127.0.0.1.nip.io:8443/
```

A browser does not automatically trust this ephemeral CA. The test does not install global trust or configure user authentication.

## Limits and evidence

The `sync-upload` middleware permits **570,425,344 bytes (544 MiB)**, matching the gateway request bound, and buffers to disk above 1 MiB. No middleware removes the namespace/Deployment path prefix. The TLS entrypoint uses `readTimeout=120s`, `writeTimeout=120s`, and `idleTimeout=180s`. The daemon still has a 45-second request timeout; ingress settings do not extend the client budget. See Traefik's [Buffering](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/buffering/) and [EntryPoints](https://doc.traefik.io/traefik/reference/install-configuration/entrypoints/) references.

The test checks:

- Certificate rejection with system trust alone and acceptance with the explicit CA.
- Rejection of missing, inactive and out-of-namespace routes.
- A real upload above 2 MiB, followed by download and SHA-256 comparison through the application ingress.
- Automatic content modification and exact baseline restoration.
- A `/plan` body sent in two pieces two seconds apart, returning 200.
- Effective controller timeout arguments.
- A reduced 1 KiB middleware limit: 512 bytes reach the gateway (404), while 2 KiB are rejected by Traefik (413).
- JSON access logs showing the retained path, router, HTTP gateway backend, upload size and 200 response, plus the 413 rejection.
- No Pod, Secret, Deployment-patch or port-forward permissions for the transition identity.
- Unchanged templates for the six previous application fixtures.

Evidence is written to `/tmp/shadok-ingress-local/evidence.json`. The full 544 MiB limit and a 120-second transfer were not exercised; effective configuration, a reduced threshold test, a 2 MiB upload and a delayed request are the bounded evidence. During rollout, old and new endpoints may briefly coexist; the test waits for convergence and does not claim atomic cutover or browser HMR.

## Local lifecycle

The controller, fixtures, certificate and relay remain after testing. The test daemon stops and its session is disabled. Close only the local listener ports with:

```sh
docker stop shadok-ingress-local
# Reopen:
docker start shadok-ingress-local
```

Setup replaces only its relay identified by `shadok.local-test=ingress`, renews its certificate and updates its releases. It does not delete the cluster or unrelated workloads, commit code or publish an internet service.

See the [complete gateway networking guide](../operator-go/internal/guidance/topics/network.md) for platform exposure, daemon destination settings and diagnostics. Run `shadok learn network` to read it in the CLI.
