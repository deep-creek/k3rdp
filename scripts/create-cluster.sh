#!/usr/bin/env bash
#
# create-cluster.sh — create the k3d cluster and map the host RDP port into it.
#
# Host localhost:3389 is forwarded by the k3d serverlb to the LoadBalancer
# Service (k3s servicelb/klipper). RDP is raw TCP, so Traefik ingress is not used.
#
set -euo pipefail

CLUSTER="${CLUSTER_NAME:-k3rdp}"

if k3d cluster list "${CLUSTER}" >/dev/null 2>&1; then
  echo "Cluster '${CLUSTER}' already exists. Delete it first with scripts/destroy.sh"
  exit 0
fi

echo "==> Creating k3d cluster '${CLUSTER}' (host :3389 -> RDP LoadBalancer)"
k3d cluster create "${CLUSTER}" \
  --port "3389:3389@loadbalancer" \
  --wait

echo "==> Nodes:"
kubectl get nodes
echo
echo "Cluster ready. Next:  scripts/build-images.sh"
