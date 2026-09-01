#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

for group in base desktop apps audio shell dev winboat; do
  log_step "Installing package group: ${group}"
  install_pacman_manifest "${DISTRO_ROOT}/packages/${group}.txt"
done

log_success "Core desktop packages installed."
