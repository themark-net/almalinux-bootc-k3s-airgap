#/bin/bash
# =====================================================================
# AlmaLinux Bootc + K3s Air-Gapped Installer Builder
# Creates a custom bootc image with preloaded K3s for single-node
# Kubernetes (simulating multi-node), then builds a bootable ISO
# with automated Kickstart install.
# Run this on an internet-connected machine with Podman.
# =====================================================================

set -euo pipefail

# Configuration
IMAGE_NAME="almalinux-k3s-airgap-bootc"
TAG="latest"
BASE_IMAGE="quay.io/almalinuxorg/almalinux-bootc:9"
OUTPUT_DIR="./output"
BUILD_DIR="./build"
K3S_VERSION="latest"  # or pin e.g. "v1.31.1+k3s1"

echo "=== Setting up directories ==="
mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}"

# Create Containerfile
cat > "${BUILD_DIR}/Containerfile" << 'EOF'
FROM quay.io/almalinuxorg/almalinux-bootc:9

# Install base tools and K3s
RUN dnf install -y curl iptables iproute net-tools \
    && dnf clean all

# Install K3s (server mode, disable traefik for custom ingress later)
RUN curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" INSTALL_K3S_EXEC="server --disable traefik --disable servicelb" sh -s -

# Enable K3s service
RUN systemctl enable k3s

# Pre-pull and save common images for air-gapping
RUN mkdir -p /var/lib/rancher/k3s/agent/images

# Pull core images (add your workload images here)
RUN crictl pull registry.k8s.io/pause:3.10 \
    && crictl pull registry.k8s.io/coredns/coredns:v1.11.3 \
    && crictl pull docker.io/rancher/klipper-lb:v0.4.0 \
    && crictl pull docker.io/rancher/local-path-provisioner:v0.0.30 \
    && crictl pull docker.io/rancher/mirrored-metrics-server:v0.7.1

# Export images to tarballs for K3s air-gap loading
RUN ctr -n k8s.io images export /var/lib/rancher/k3s/agent/images/k8s-core.tar.gz \
    $(ctr -n k8s.io images list -q | grep -E 'pause|coredns|klipper|local-path|metrics-server')

# Optional: Add your custom configs, GitLab runner, jump-box SSH setup, etc.
# COPY k3s-config.yaml /etc/rancher/k3s/config.yaml
# RUN systemctl enable your-gitlab-runner-service

# Lock down networking (air-gap friendly)
RUN systemctl disable --now firewalld || true
EOF

echo "=== Building custom bootc image ==="
podman build -t "${IMAGE_NAME}:${TAG}" -f "${BUILD_DIR}/Containerfile" "${BUILD_DIR}"

# Create config.toml with Kickstart for unattended install
cat > "${BUILD_DIR}/config.toml" << 'EOF'
[customizations.installer.kickstart]
contents = """
text --non-interactive
zerombr
clearpart --all --initlabel --disklabel=gpt
autopart --noswap --type=lvm --nohome
network --bootproto=dhcp --device=link --activate --onboot=on
rootpw --lock
reboot --eject
"""
EOF

echo "=== Building bootable ISO with bootc-image-builder ==="
mkdir -p "${OUTPUT_DIR}"

sudo podman run --rm -it --privileged \
  --pull=newer \
  --security-opt label=type:unconfined_t \
  -v "${OUTPUT_DIR}:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v "${BUILD_DIR}/config.toml:/config.toml:ro" \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type iso \
  --config /config.toml \
  "${IMAGE_NAME}:${TAG}"

echo "=== Build complete! ==="
echo "ISO is ready at: ${OUTPUT_DIR}/ (look for *.iso)"
echo ""
echo "Next steps:"
echo "1. Copy the ISO to a USB drive (e.g., dd if=*.iso of=/dev/sdX bs=4M status=progress)"
echo "2. Boot target machine from USB → it will auto-install the bootc system with K3s"
echo "3. Post-install: Set up SSH key-based access restricted to jump box"
echo "4. Configure port forwarding on jump box for GitLab runner jobs"
echo ""
echo "For multi-node simulation: Add more nodes later via bootc upgrade or additional ISOs."
