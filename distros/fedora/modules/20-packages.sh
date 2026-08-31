#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

log_step 'Updating the Fedora installation'
as_root dnf -y upgrade --refresh

for manifest in core desktop shell apps; do
  log_step "Installing ${manifest} packages"
  install_dnf_manifest "${DISTRO_ROOT}/packages/${manifest}.txt"
done

log_step 'Preparing the GPU driver stack'
if ! gpu="$(gpu_vendor)"; then
  mapfile -t hardware < <(gpu_hardware_vendors)
  if ((${#hardware[@]} > 1)); then
    die "Multiple GPU vendors detected (${hardware[*]}). Pick one interactively with ./install.sh, or set WORKSTATION_GPU=nvidia|amd|intel|none."
  fi
  log_warn 'No GPU vendor could be detected or selected; skipping the GPU driver stack.'
  log_warn 'Choose one with ./install.sh or WORKSTATION_GPU=nvidia|amd|intel|none and rerun module 20.'
else
  # Persist the resolved vendor: startup.lua reads it to decide whether the
  # NVIDIA environment variables apply to this machine's session.
  mkdir -p -- "$(dirname -- "$(gpu_state_file)")"
  printf '%s\n' "${gpu}" >"$(gpu_state_file)"
  case ${gpu} in
    none)
      log_warn 'GPU vendor set to none (VM or headless); skipping the GPU driver stack.'
      ;;
    nvidia)
      install_dnf_manifest "${DISTRO_ROOT}/packages/nvidia.txt"
      if selection_is_skipped nvidia akmod-nvidia-open; then
        log_warn 'akmod-nvidia-open is deselected; skipping the kernel module build.'
      else
        latest_kernel="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | sort -V | tail -n1)"
        [[ -n ${latest_kernel} ]] || die 'No installed Fedora kernel was found.'
        as_root akmods --force --kernels "${latest_kernel}"
        modinfo -k "${latest_kernel}" nvidia >/dev/null 2>&1 \
          || die "The NVIDIA module was not built for ${latest_kernel}. Review the akmods output before rebooting."
      fi
      ;;
    amd)
      install_dnf_manifest "${DISTRO_ROOT}/packages/amd.txt"
      ;;
    intel)
      install_dnf_manifest "${DISTRO_ROOT}/packages/intel.txt"
      ;;
  esac
fi

log_success 'Core, desktop, shell, application, and GPU RPMs are installed.'
