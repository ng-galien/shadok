#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-shadok-go-e2e}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-/tmp/shadok-go-e2e.kubeconfig}"
NAMESPACE="${NAMESPACE:-shadok-live-system}"
RELEASE_NAME="${RELEASE_NAME:-runtime}"
if [[ "${SKIP_BUILD:-0}" != 1 ]]; then make -C "$REPO_ROOT/operator-go" generic-images; fi
for component in operator gateway tools; do kind load docker-image --name "$CLUSTER_NAME" "shadok-$component:local"; done
kubectl --kubeconfig "$KUBECONFIG_PATH" --context "kind-$CLUSTER_NAME" apply --server-side -f "$REPO_ROOT/operator-go/chart/crds"
helm upgrade --install "$RELEASE_NAME" "$REPO_ROOT/operator-go/chart" \
  --kubeconfig "$KUBECONFIG_PATH" --kube-context "kind-$CLUSTER_NAME" \
  --namespace "$NAMESPACE" --create-namespace \
  --set operator.image.tag=local --set operator.toolImage.tag=local --set gateway.image.tag=local \
  --wait --timeout 5m "$@"
