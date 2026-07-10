#!/usr/bin/env bash
#
# deploy.sh — apply the Kustomize manifests and wait for both pods to be ready.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="k3rdp"

echo "==> Applying manifests"
kubectl apply -k "${ROOT}/manifests"

echo "==> Waiting for deployments to become available"
kubectl -n "${NS}" rollout status deploy/x11rdp --timeout=180s
kubectl -n "${NS}" rollout status deploy/qtapp  --timeout=180s

echo
echo "==> Pods:"
kubectl -n "${NS}" get pods -o wide
echo
echo "==> Services:"
kubectl -n "${NS}" get svc
echo
echo "Deployed. Connect an RDP client with:  scripts/connect.sh"
