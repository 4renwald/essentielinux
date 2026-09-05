#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

log_step 'Installing application packages'
install_pacman_manifest "${DISTRO_ROOT}/packages/apps.txt"

log_step 'Installing AUR packages'
install_yay_manifest "${DISTRO_ROOT}/packages/aur.txt"

log_success 'Application packages installed.'
