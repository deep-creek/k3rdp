#!/usr/bin/env bash
#
# destroy.sh — delete the k3d cluster (and everything in it).
#
set -euo pipefail

CLUSTER="${CLUSTER_NAME:-k3rdp}"

if ! k3d cluster list "${CLUSTER}" >/dev/null 2>&1; then
  echo "Cluster '${CLUSTER}' does not exist. Nothing to do."
  exit 0
fi

echo "==> Deleting k3d cluster '${CLUSTER}'"
k3d cluster delete "${CLUSTER}"
echo "Done."
