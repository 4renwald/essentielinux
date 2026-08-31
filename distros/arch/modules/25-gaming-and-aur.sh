#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

# Install these only after module 20 has selected the correct Vulkan provider.
log_step "Installing the gaming package group"
install_pacman_manifest "${DISTRO_ROOT}/packages/gaming.txt"

log_step "Installing AUR packages"
install_paru_manifest "${DISTRO_ROOT}/packages/aur.txt"

log_success "Gaming and AUR packages installed."
