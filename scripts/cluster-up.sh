#!/usr/bin/env bash
set -euo pipefail
CLUSTER_NAME="${CLUSTER_NAME:-shadok-go-e2e}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-/tmp/shadok-go-e2e.kubeconfig}"
if kind get clusters | grep -Fx -- "$CLUSTER_NAME" >/dev/null; then
  kind export kubeconfig --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG_PATH"
else
  kind create cluster --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG_PATH" --wait 120s
fi
kubectl --kubeconfig "$KUBECONFIG_PATH" --context "kind-$CLUSTER_NAME" cluster-info
