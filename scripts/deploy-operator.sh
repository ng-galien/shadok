#!/usr/bin/env bash
#
# deploy-operator.sh - build the Shadok operator image and install the chart
#
# Idempotent. Safe to re-run after every code change while iterating.
#
# Steps:
#   1. Build and push the operator image to localhost:5001 via Jib
#      (./gradlew :operator:build does this under env=kind, configured
#      in operator/build.gradle.kts).
#   2. Render + helm upgrade --install the chart from
#      operator/build/chart/operator (the rendered chart with resolved
#      Gradle placeholders, NOT the src/main/chart/ template).
#   3. Wait for the deployment to be ready and print a quick status.
#
# Requirements: the cluster must already be up (run cluster-up.sh first).
#
# Env overrides:
#   NAMESPACE     default: shadok
#   RELEASE_NAME  default: shadok
#   SKIP_BUILD=1  skip ./gradlew build (use the last-built image as-is)
#
set -euo pipefail

NAMESPACE="${NAMESPACE:-shadok}"
RELEASE_NAME="${RELEASE_NAME:-shadok}"
SKIP_BUILD="${SKIP_BUILD:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHART_DIR="${REPO_ROOT}/operator/build/chart/operator"

log() { printf '\033[1;34m▶\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

for cmd in kubectl helm; do
  command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
done

kubectl cluster-info >/dev/null 2>&1 || die "no reachable cluster; run ./scripts/cluster-up.sh first"

# ---------------------------------------------------------------------------
# Build + push operator image
# ---------------------------------------------------------------------------
if [ "${SKIP_BUILD}" != "1" ]; then
  log "building and pushing operator image via Jib"
  (cd "${REPO_ROOT}" && ./gradlew :operator:build) >/dev/null
  ok "image pushed to localhost:5001/shadok-operator:latest"
else
  log "SKIP_BUILD=1 -> skipping image build"
fi

[ -d "${CHART_DIR}" ] || die "rendered chart not found at ${CHART_DIR} (did the build run?)"

# ---------------------------------------------------------------------------
# Helm install / upgrade
# ---------------------------------------------------------------------------
log "helm upgrade --install ${RELEASE_NAME} in namespace ${NAMESPACE}"
helm upgrade --install "${RELEASE_NAME}" "${CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --wait \
  --timeout 5m >/dev/null
ok "chart installed"

# ---------------------------------------------------------------------------
# Wait + status
# ---------------------------------------------------------------------------
DEPLOY_NAME="$(kubectl -n "${NAMESPACE}" get deploy -l app.kubernetes.io/instance="${RELEASE_NAME}" -o jsonpath='{.items[0].metadata.name}')"
log "waiting for deployment/${DEPLOY_NAME} rollout"
kubectl -n "${NAMESPACE}" rollout status "deployment/${DEPLOY_NAME}" --timeout 3m

printf '\n'
ok "operator deployed"
kubectl -n "${NAMESPACE}" get deploy,pods,svc -l app.kubernetes.io/instance="${RELEASE_NAME}"
printf '\n'
kubectl get mutatingwebhookconfiguration -l app.kubernetes.io/instance="${RELEASE_NAME}" 2>/dev/null || true
printf '\nLogs: kubectl -n %s logs -f deploy/%s\n' "${NAMESPACE}" "${DEPLOY_NAME}"
