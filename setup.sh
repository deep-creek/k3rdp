#!/usr/bin/env bash
#
# setup.sh — install the tooling needed for the k3rdp stack on Fedora.
#
# Run with sudo:  sudo ./setup.sh
#
# Installs standard Fedora packages via dnf (kubectl, kustomize, helm, freerdp)
# and the k3d binary into /usr/bin (k3d is not packaged in Fedora). Docker is
# expected to be already installed and running.
#
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "This script installs system packages and must be run with sudo:" >&2
  echo "  sudo $0" >&2
  exit 1
fi

echo "==> Checking Docker (must already be installed and running)"
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found. Install and start Docker first." >&2
  exit 1
fi
docker info >/dev/null 2>&1 || {
  echo "ERROR: Docker daemon not reachable. Start it with: systemctl start docker" >&2
  exit 1
}
echo "    Docker OK: $(docker --version)"

# kubectl is shipped in the 'kubernetes<ver>-client' package on Fedora and
# provides /usr/bin/kubectl. Resolve the concrete package name dynamically so
# this keeps working as Fedora bumps the bundled Kubernetes version.
echo "==> Resolving kubectl package"
KUBECTL_PKG="$(dnf -q provides '/usr/bin/kubectl' 2>/dev/null \
  | grep -oE '^kubernetes[0-9.]*-client' | head -n1 || true)"
if [[ -z "${KUBECTL_PKG}" ]]; then
  KUBECTL_PKG="kubernetes-client"   # fallback name
fi
echo "    Using: ${KUBECTL_PKG}"

echo "==> Installing Fedora packages (kubectl, kustomize, helm, freerdp)"
dnf install -y "${KUBECTL_PKG}" kustomize helm freerdp

# k3d is not in the Fedora repos. Install its official binary into /usr/bin
# (per requirement: not /usr/local). The upstream installer honors K3D_INSTALL_DIR.
if command -v k3d >/dev/null 2>&1; then
  echo "==> k3d already installed: $(k3d version | head -n1)"
else
  echo "==> Installing k3d binary into /usr/bin"
  curl -sfL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh \
    | K3D_INSTALL_DIR=/usr/bin USE_SUDO=false bash
fi

echo
echo "==> Installed versions:"
k3d version | head -n1
kubectl version --client 2>/dev/null | head -n1 || kubectl version --client --output=yaml 2>/dev/null | head -n1
kustomize version 2>/dev/null | head -n1
helm version --short 2>/dev/null || true
xfreerdp --version 2>/dev/null | head -n1 || true
echo
echo "Setup complete. Next:  scripts/create-cluster.sh"
