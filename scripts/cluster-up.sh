#!/usr/bin/env bash
#
# cluster-up.sh - bring up a local Kind cluster for Shadok development
#
# Creates (idempotently):
#   1. A local Docker registry container on localhost:5001 that Kind nodes
#      can pull from ("kind-registry"). Shared across cluster recreations.
#   2. A Kind cluster named "shadok-dev" with:
#      - the local registry wired in via containerd config patches
#      - the host directory `pods/` mounted read-only into every node at
#        /mnt/shadok-pods, so ProjectSource hostPath PVs can expose live
#        source trees without any sync step
#      - a cache directory mounted read-write at /mnt/shadok-cache for
#        DependencyCache PVs (shared .m2, .gradle, .npm, etc.)
#   3. cert-manager installed via its upstream chart (needed by the
#      operator Helm chart to issue the webhook TLS certificate).
#
# Running this script on an existing cluster is a no-op apart from
# reinstalling/upgrading cert-manager. It never recreates the cluster.
# Pass --recreate to force a wipe.
#
# Requirements: docker, kind, kubectl, helm.
#
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-shadok-dev}"
REGISTRY_NAME="${REGISTRY_NAME:-kind-registry}"
REGISTRY_PORT="${REGISTRY_PORT:-5001}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.16.2}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PODS_DIR="${REPO_ROOT}/pods"
CACHE_DIR="${REPO_ROOT}/.shadok-cache"

RECREATE=false
for arg in "$@"; do
  case "$arg" in
    --recreate) RECREATE=true ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

log() { printf '\033[1;34m▶\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

for cmd in docker kind kubectl helm; do
  command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
done

docker info >/dev/null 2>&1 || die "docker daemon is not running"

# ---------------------------------------------------------------------------
# Local registry
# ---------------------------------------------------------------------------
log "ensuring local registry '${REGISTRY_NAME}' on port ${REGISTRY_PORT}"
if [ "$(docker inspect -f '{{.State.Running}}' "${REGISTRY_NAME}" 2>/dev/null || true)" != "true" ]; then
  # Clean up any stopped container with the same name.
  docker rm "${REGISTRY_NAME}" >/dev/null 2>&1 || true
  docker run -d --restart=always \
    -p "127.0.0.1:${REGISTRY_PORT}:5000" \
    --name "${REGISTRY_NAME}" \
    registry:2 >/dev/null
  ok "started ${REGISTRY_NAME}"
else
  ok "${REGISTRY_NAME} already running"
fi

# ---------------------------------------------------------------------------
# Host directories for source sync and dependency cache
# ---------------------------------------------------------------------------
[ -d "${PODS_DIR}" ] || die "expected pods directory at ${PODS_DIR}"
mkdir -p "${CACHE_DIR}"
ok "host mounts ready: ${PODS_DIR} (ro), ${CACHE_DIR} (rw)"

# ---------------------------------------------------------------------------
# Kind cluster
# ---------------------------------------------------------------------------
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  if [ "${RECREATE}" = "true" ]; then
    log "deleting existing cluster '${CLUSTER_NAME}' (--recreate)"
    kind delete cluster --name "${CLUSTER_NAME}"
  else
    ok "cluster '${CLUSTER_NAME}' already exists (use --recreate to wipe)"
  fi
fi

if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  log "creating Kind cluster '${CLUSTER_NAME}'"
  cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${REGISTRY_PORT}"]
    endpoint = ["http://${REGISTRY_NAME}:5000"]
nodes:
- role: control-plane
  extraMounts:
  - hostPath: ${PODS_DIR}
    containerPath: /mnt/shadok-pods
    readOnly: true
  - hostPath: ${CACHE_DIR}
    containerPath: /mnt/shadok-cache
    readOnly: false
EOF
  ok "cluster created"
fi

# Connect the registry to the kind network so the control-plane can resolve
# it by the ${REGISTRY_NAME} hostname referenced in containerdConfigPatches.
if ! docker network inspect kind 2>/dev/null | grep -q "\"${REGISTRY_NAME}\""; then
  log "connecting ${REGISTRY_NAME} to the kind docker network"
  docker network connect kind "${REGISTRY_NAME}" 2>/dev/null || true
fi

# Register the local registry with the cluster per the kind docs pattern,
# so `docker build ... localhost:5001/...` then `docker push` works from
# the host *and* `kubectl apply` can pull the resulting image from inside.
kubectl apply -f - <<EOF >/dev/null
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REGISTRY_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
ok "local-registry-hosting ConfigMap applied"

# ---------------------------------------------------------------------------
# cert-manager
# ---------------------------------------------------------------------------
log "installing/upgrading cert-manager ${CERT_MANAGER_VERSION}"
helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
helm repo update jetstack >/dev/null
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version "${CERT_MANAGER_VERSION}" \
  --set crds.enabled=true \
  --wait \
  --timeout 5m >/dev/null
ok "cert-manager ready"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n'
ok "cluster '${CLUSTER_NAME}' is up"
printf '  kubectl context: %s\n' "$(kubectl config current-context)"
printf '  registry:        localhost:%s\n' "${REGISTRY_PORT}"
printf '  host mounts:     %s -> /mnt/shadok-pods (ro)\n' "${PODS_DIR}"
printf '                   %s -> /mnt/shadok-cache (rw)\n' "${CACHE_DIR}"
printf '\nNext: ./scripts/deploy-operator.sh\n'
