#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$ROOT/scripts/cluster-up.sh"
exec "$ROOT/scripts/deploy-operator.sh" "$@"
