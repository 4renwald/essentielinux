#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

log_step 'Removing conflicting and superseded desktop packages'
read_manifest "${DISTRO_ROOT}/packages/remove.txt"

installed=()
for package in "${PACKAGES[@]}"; do
  rpm -q "${package}" >/dev/null 2>&1 && installed+=("${package}")
done

if ((${#installed[@]} == 0)); then
  log_success 'No conflicting or superseded desktop packages are installed.'
else
  as_root dnf -y remove "${installed[@]}"
  log_success "Removed: ${installed[*]}"
fi

# Fedora's protected base includes vim-minimal. Removing vim-enhanced leaves the
# base editor intact, and Nano remains installed by packages/core.txt.
