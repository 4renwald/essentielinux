#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

[[ -r /etc/os-release ]] || die '/etc/os-release is missing.'
# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == fedora ]] || die "This distro targets Fedora, not ${ID:-an unknown OS}."
(( VERSION_ID == 44 )) || die "This setup is validated for Fedora 44; found ${VERSION_ID}."
[[ $(uname -m) == x86_64 ]] || die 'This configuration targets an x86_64 workstation.'

for command in curl git rpm dnf lspci systemctl install findmnt tar sha256sum; do
  require_command "${command}"
done

[[ -z ${WORKSTATION_GPU:-} ]] || valid_gpu_vendor "${WORKSTATION_GPU}" \
  || die "Invalid WORKSTATION_GPU '${WORKSTATION_GPU}'. Use nvidia, amd, intel, or none."

mapfile -t detected < <(gpu_driver_vendors)
if ((${#detected[@]} > 0)); then
  gpu_detect_display="${detected[*]}"
else
  gpu_detect_display='not detected'
fi

log_success "Fedora ${VERSION_ID} x86_64 passed preflight."
log_info "GPU driver stacks: ${gpu_detect_display} (override with WORKSTATION_GPU or --gpu)"
