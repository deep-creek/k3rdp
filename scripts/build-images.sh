#!/usr/bin/env bash
#
# build-images.sh — build the two container images and import them into k3d.
#
# k3d nodes use containerd, not the host Docker daemon, so images built here
# must be imported into the cluster. Manifests use imagePullPolicy: IfNotPresent.
#
set -euo pipefail

CLUSTER="${CLUSTER_NAME:-k3rdp}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

X11RDP_IMAGE="k3rdp/x11rdp:dev"
QTAPP_IMAGE="k3rdp/qtapp:dev"

echo "==> Building ${X11RDP_IMAGE}"
docker build -t "${X11RDP_IMAGE}" "${ROOT}/images/x11rdp"

echo "==> Building ${QTAPP_IMAGE}"
docker build -t "${QTAPP_IMAGE}" "${ROOT}/images/qtapp"

echo "==> Importing images into k3d cluster '${CLUSTER}'"
k3d image import "${X11RDP_IMAGE}" "${QTAPP_IMAGE}" -c "${CLUSTER}"

echo
echo "Images built and imported. Next:  scripts/deploy.sh"
