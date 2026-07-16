# AlmaLinux Bootc + K3s Air-Gapped Installer

Automated builder for a bootable ISO that installs an air-gapped AlmaLinux system in **bootc** mode with a pre-configured single-node K3s Kubernetes cluster.

## Features
- Uses official AlmaLinux bootc image
- Preloads K3s and core container images for fully offline operation
- Automated Kickstart installation via bootc-image-builder
- Ready for jump-box SSH/port-forward access + GitLab runners

## Quick Start
1. Clone this repo: `git clone https://github.com/themark-net/almalinux-bootc-k3s-airgap.git`
2. Run `./build-airgap-bootc-k3s.sh` on an internet-connected machine (requires Podman and sudo).
3. The ISO will be in `./output/`.
4. Write ISO to USB: `dd if=output/*.iso of=/dev/sdX bs=4M status=progress && sync`
5. Boot the target machine from USB — installation is fully automated.

## Post-Install
- SSH access locked to jump box (configure keys/firewall)
- K3s running with preloaded images
- Extend with your workloads, GitLab Runner, etc.

## Customization
Edit the script's Containerfile section to add packages, images, services.

For production multi-node: Deploy additional bootc nodes and join them to the cluster.

**Repo**: https://github.com/themark-net/almalinux-bootc-k3s-airgap