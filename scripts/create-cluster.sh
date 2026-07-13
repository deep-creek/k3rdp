#!/usr/bin/env bash
#
# create-cluster.sh — create the k3d cluster and map the host access ports in.
#
# Host localhost:33389 (RDP) and localhost:35900 (VNC) are forwarded by the k3d
# serverlb to the LoadBalancer Services (k3s servicelb/klipper) on their standard
# ports (3389/5900). The host ports are offset by +30000 to avoid clashing with a
# local RDP/VNC server. Both are raw TCP (no Traefik). Ports bind to 127.0.0.1.
#
set -euo pipefail

CLUSTER="${CLUSTER_NAME:-k3rdp}"

if k3d cluster list "${CLUSTER}" >/dev/null 2>&1; then
  echo "Cluster '${CLUSTER}' already exists. Delete it first with scripts/destroy.sh"
  exit 0
fi

echo "==> Creating k3d cluster '${CLUSTER}' (host :33389 RDP + :35900 VNC)"
k3d cluster create "${CLUSTER}" \
  --port "127.0.0.1:33389:3389@loadbalancer" \
  --port "127.0.0.1:35900:5900@loadbalancer" \
  --wait

echo "==> Nodes:"
kubectl get nodes
echo
echo "Cluster ready. Next:  scripts/build-images.sh"
