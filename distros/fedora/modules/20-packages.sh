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

# Fedora keeps most hardware drivers in the kernel and ships their firmware as
# a maintained comps group. Installing the group lets Fedora's kernel/udev
# device matching choose the correct firmware without hard-coding a Wi-Fi
# vendor or chipset in this repository.
log_step 'Installing Fedora hardware firmware support'
as_root dnf -y group install hardware-support

log_step 'Preparing the GPU driver stack'
mapfile -t gpu_vendors < <(gpu_driver_vendors)
if ((${#gpu_vendors[@]} == 0)); then
  log_warn 'No GPU vendor could be detected or selected; skipping the GPU driver stack.'
else
  log_info "Installing driver stacks for: ${gpu_vendors[*]}."
  for gpu in "${gpu_vendors[@]}"; do
    case ${gpu} in
      nvidia)
        log_info "RPM Fusion's akmod-nvidia will select the NVIDIA module for this PCI ID."
        install_dnf_manifest "${DISTRO_ROOT}/packages/nvidia.txt"
        if selection_is_skipped nvidia akmod-nvidia; then
          log_warn 'akmod-nvidia is deselected; skipping the kernel module build.'
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
  done
fi

log_success 'Core, desktop, shell, application, and GPU RPMs are installed.'
