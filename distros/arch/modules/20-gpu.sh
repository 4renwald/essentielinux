#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

require_command lspci

mapfile -t gpu_vendors < <(gpu_driver_vendors)

declare -a hardware_packages=() aur_packages=()
declare -A package_seen=()

add_hardware_package() {
  local package=$1
  if [[ -z ${package_seen[${package}]+x} ]]; then
    hardware_packages+=("${package}")
    package_seen[${package}]=1
  fi
}

add_aur_package() {
  local package=$1
  if [[ -z ${package_seen[${package}]+x} ]]; then
    aur_packages+=("${package}")
    package_seen[${package}]=1
  fi
}

# CPU microcode is independent of the graphics stack.
cpu_vendor="$(awk -F: '/^[[:space:]]*vendor_id[[:space:]]*:/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' /proc/cpuinfo)"
case "${cpu_vendor}" in
  AuthenticAMD) add_hardware_package amd-ucode ;;
  GenuineIntel) add_hardware_package intel-ucode ;;
  *) log_warn "Unknown CPU vendor '${cpu_vendor:-missing}'; install the appropriate microcode package manually." ;;
esac

if ((${#gpu_vendors[@]} == 0)); then
  log_warn 'No GPU was detected; installing CPU microcode only.'
else
  log_info "Installing driver stacks for: ${gpu_vendors[*]}."
fi

for gpu in "${gpu_vendors[@]}"; do
  case ${gpu} in
    amd)
      # The kernel's amdgpu driver and Mesa userspace cover supported AMD GPUs.
      for package in mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon; do
        add_hardware_package "${package}"
      done
      ;;
    intel)
      # Mesa plus both VA-API packages cover current and older Intel iGPUs.
      for package in mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver; do
        add_hardware_package "${package}"
      done
      ;;
    nvidia)
      nvidia_flavor="$(nvidia_kernel_module_flavor)" \
        || die 'NVIDIA was detected but no display PCI ID could be read.'
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
        || die 'No supported Arch kernel was found. Install linux, linux-lts, linux-zen, or linux-hardened first.'

      if [[ ${nvidia_flavor} == unsupported ]]; then
        die "NVIDIA PCI ID is older than the supported 580xx branch. Select a maintained legacy driver manually: $(nvidia_display_pci_ids | paste -sd ',')."
      elif [[ ${nvidia_flavor} == proprietary ]]; then
        require_command paru
        log_info 'NVIDIA PCI ID requires the proprietary 580xx kernel module.'
        add_aur_package nvidia-580xx-dkms
        add_aur_package nvidia-580xx-utils
        add_aur_package lib32-nvidia-580xx-utils
        for kernel in "${installed_kernels[@]}"; do
          add_hardware_package "${kernel}-headers"
        done
      elif [[ ${use_nvidia_dkms} == true ]]; then
        add_hardware_package nvidia-open-dkms
        for kernel in "${installed_kernels[@]}"; do
          add_hardware_package "${kernel}-headers"
        done
      else
        for kernel in "${installed_kernels[@]}"; do
          case "${kernel}" in
            linux) add_hardware_package nvidia-open ;;
            linux-lts) add_hardware_package nvidia-open-lts ;;
          esac
        done
      fi

      # VA-API front end for NVDEC. Mesa already covers AMD and Intel.
      add_hardware_package libva-nvidia-driver
      ;;
  esac
done

if ((${#gpu_vendors[@]} > 0)); then
  add_hardware_package mesa-utils
  add_hardware_package vulkan-tools
  add_hardware_package libva-utils
fi

if ((${#hardware_packages[@]} > 0)); then
  log_step 'Installing Arch graphics drivers and CPU microcode'
  printf '  %s\n' "${hardware_packages[@]}"
  as_root pacman -S --needed --noconfirm "${hardware_packages[@]}"
fi

if ((${#aur_packages[@]} > 0)); then
  log_step 'Installing the legacy NVIDIA driver from the AUR'
  printf '  %s\n' "${aur_packages[@]}"
  paru -S --aur --needed "${aur_packages[@]}"
fi

# NVIDIA packages handle their own sleep integration. This installer does not
# add module parameters or service overrides on top of the packaged defaults.

if command -v mkinitcpio >/dev/null 2>&1; then
  log_step 'Regenerating initramfs images'
  as_root mkinitcpio -P
fi

log_success 'Arch hardware support is installed. Reboot before judging driver health.'
