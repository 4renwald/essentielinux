#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

require_command lspci

# The GPU vendor comes from the same picker Fedora uses: --gpu / WORKSTATION_GPU,
# the saved interactive choice, or single-GPU auto-detection. Arch keeps the
# detected vendor as the picker default, so a fresh machine usually just
# confirms. Multi-GPU ambiguity dies here instead of installing the wrong stack.
gpu=''
if ! gpu="$(gpu_vendor)"; then
  mapfile -t hardware < <(gpu_hardware_vendors)
  if ((${#hardware[@]} > 1)); then
    die "Multiple GPU vendors detected (${hardware[*]}). Pick one interactively with ./install.sh, or set WORKSTATION_GPU=nvidia|amd|intel|none."
  fi
  gpu=''
fi

if [[ -z ${gpu} ]]; then
  log_warn 'No GPU vendor could be detected or selected; skipping the GPU driver stack.'
  log_warn 'Choose one with ./install.sh or WORKSTATION_GPU=nvidia|amd|intel|none and rerun module 20.'
  exit 0
fi

declare -a hardware_packages=()
declare -A package_seen=()

add_hardware_package() {
  local package=$1
  if [[ -z ${package_seen[${package}]+x} ]]; then
    hardware_packages+=("${package}")
    package_seen[${package}]=1
  fi
}

# CPU microcode is picked independently of the GPU choice.
cpu_vendor="$(awk -F: '/^[[:space:]]*vendor_id[[:space:]]*:/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' /proc/cpuinfo)"
case "${cpu_vendor}" in
  AuthenticAMD) add_hardware_package amd-ucode ;;
  GenuineIntel) add_hardware_package intel-ucode ;;
  *) log_warn "Unknown CPU vendor '${cpu_vendor:-missing}'; install the appropriate microcode package manually." ;;
esac

case ${gpu} in
  none)
    log_warn 'GPU vendor set to none (VM or headless); skipping the GPU driver stack.'
    ;;
  amd)
    # mesa also provides AMD's VA-API video-decoding driver.
    for package in mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon; do
      add_hardware_package "${package}"
    done
    ;;
  intel)
    for package in mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver; do
      add_hardware_package "${package}"
    done
    ;;
  nvidia)
    nvidia_devices="$(lspci -nn | grep -Ei 'VGA|3D|Display' | grep -i nvidia || true)"
    if ! grep -Eqi 'RTX|GTX 16|TITAN RTX|Tesla T4|\[(TU|GA|AD|GB)[0-9]+' <<< "${nvidia_devices}"; then
      die "The selected NVIDIA GPU is not recognized as Turing or newer: ${nvidia_devices//$'\n'/; }. Select the driver from ArchWiki's NVIDIA table manually."
    fi

    found_supported_kernel=false
    use_nvidia_dkms=false
    declare -a installed_kernels=()
    for kernel in linux linux-lts linux-zen linux-hardened; do
      if pacman -Q "${kernel}" >/dev/null 2>&1; then
        installed_kernels+=("${kernel}")
        found_supported_kernel=true
        if [[ ${kernel} == linux-zen || ${kernel} == linux-hardened ]]; then
          use_nvidia_dkms=true
        fi
      fi
    done
    [[ ${found_supported_kernel} == true ]] \
      || die "No supported Arch kernel was found. Install linux, linux-lts, linux-zen, or linux-hardened first."

    declare -a wanted_nvidia_modules=()
    if [[ ${use_nvidia_dkms} == true ]]; then
      wanted_nvidia_modules=(nvidia-open-dkms)
      add_hardware_package nvidia-open-dkms
      for kernel in "${installed_kernels[@]}"; do
        add_hardware_package "${kernel}-headers"
      done
    else
      for kernel in "${installed_kernels[@]}"; do
        case "${kernel}" in
          linux) wanted_nvidia_modules+=(nvidia-open); add_hardware_package nvidia-open ;;
          linux-lts) wanted_nvidia_modules+=(nvidia-open-lts); add_hardware_package nvidia-open-lts ;;
        esac
      done
    fi

    # nvidia-open-dkms conflicts with nvidia-open and with the NVIDIA-MODULE
    # virtual package, so the prebuilt and DKMS implementations can never be
    # installed together. pacman answers "no" to conflict prompts under
    # --noconfirm, which would abort the run with an opaque dependency error.
    # Detect the switch here and explain it instead.
    declare -a stale_nvidia_modules=()
    wanted_nvidia_set=" ${wanted_nvidia_modules[*]} "
    while IFS= read -r installed_module; do
      [[ -n ${installed_module} ]] || continue
      if [[ ${wanted_nvidia_set} != *" ${installed_module} "* ]]; then
        stale_nvidia_modules+=("${installed_module}")
      fi
    done < <(pacman -Qq nvidia-open nvidia-open-lts nvidia-open-dkms 2>/dev/null)

    if [[ ${#stale_nvidia_modules[@]} -gt 0 ]]; then
      die "Installed NVIDIA kernel module package(s) '${stale_nvidia_modules[*]}' do not match the set this kernel selection needs ('${wanted_nvidia_modules[*]}'). These implementations conflict and cannot be swapped unattended. Switch deliberately, then run this module again:
    sudo pacman -S ${wanted_nvidia_modules[*]}"
    fi

    for package in nvidia-utils lib32-nvidia-utils; do
      add_hardware_package "${package}"
    done

    # VA-API front end for NVDEC. Without it Firefox-based browsers decode video
    # on the CPU; mesa already covers this for AMD and Intel.
    add_hardware_package libva-nvidia-driver
    ;;
esac

if [[ ${gpu} != none ]]; then
  add_hardware_package mesa-utils
  add_hardware_package vulkan-tools
  add_hardware_package libva-utils
fi

log_step "Installing Arch graphics drivers and CPU microcode"
printf '  %s\n' "${hardware_packages[@]}"
as_root pacman -S --needed --noconfirm "${hardware_packages[@]}"

# Video-memory preservation across sleep needs no configuration here. Since the
# 595 series, nvidia-utils ships /usr/lib/modprobe.d/nvidia-sleep.conf with
# NVreg_UseKernelSuspendNotifiers=1 and NVreg_TemporaryFilePath=/var/tmp, and
# the open kernel modules handle save/restore in-kernel. The older
# NVreg_PreserveVideoMemoryAllocations parameter and the nvidia-suspend,
# nvidia-resume and nvidia-hibernate services belong to the 430-590 drivers;
# Arch's own nvidia-utils.install disables those services on upgrade.

if command -v mkinitcpio >/dev/null 2>&1; then
  log_step "Regenerating initramfs images"
  as_root mkinitcpio -P
fi

log_success "Arch hardware support is installed. Reboot before judging driver health."
