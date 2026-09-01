#!/usr/bin/env bash
# Fedora catalogue: everything the engine needs to know about this distro.
# Sourced by install.sh after DISTRO_ID/DISTRO_ROOT are resolved.

DISTRO_INFO='Fedora - Hyprland - Noctalia'

MODULE_IDS=(00 10 20 25 26 27 30 35 40 50 55 60)
MODULE_NAMES=(
  'Preflight'
  'Repositories'
  'Base packages'
  'Audio'
  'Gaming'
  'Printing'
  'Upstream & Flatpak'
  'Wallpapers'
  'System'
  'Dotfiles'
  'Video pipeline'
  'Greeter'
)
MODULE_HINTS=(
  'Verify Fedora, x86_64, and required tooling'
  'RPM Fusion, COPR, vendor repositories, and Flathub'
  'System update plus core, desktop, shell, apps, toolchains, WinBoat, and the GPU driver'
  'PipeWire, WirePlumber, and Bluetooth codecs'
  'Steam, GameMode, MangoHud, Gamescope, NTSYNC, and Wine'
  'CUPS, HPLIP, and Gutenprint'
  'Upstream CLIs, fonts, cursor, vendor RPMs, and Flatpak apps'
  'Clone the managed wallpaper collection'
  'zram, VM tunables, services, Snapper, and the Fish login shell'
  'Deploy Hyprland, Noctalia, Ghostty, and terminal configuration'
  'mpv shaders and the shader pack link'
  'greetd and the Noctalia Greeter login screen'
)

# Steps that elevate; matches the privileged operations inside each module.
ROOT_MODULES=(10 20 25 26 27 30 40 60)

declare -A MANIFEST_LABELS=(
  [core]='Core system'
  [desktop]='Desktop & Hyprland'
  [shell]='Terminal & shell'
  [apps]='Applications'
  [audio]='Audio'
  [dev]='Language toolchains'
  [winboat]='WinBoat host stack'
  [gaming]='Gaming'
  [printing]='Printing'
  [upstream]='Upstream tools & vendor apps'
  [flatpaks]='Flathub applications'
  [nvidia]='NVIDIA driver'
  [amd]='AMD driver'
  [intel]='Intel driver'
)

# Fill MANIFESTS with the selectable package groups of a step.
step_manifests() {
  local id=$1 gpu
  MANIFESTS=()
  case ${id} in
    20)
      MANIFESTS=(core desktop shell apps dev winboat)
      while IFS= read -r gpu; do
        MANIFESTS+=("${gpu}")
      done < <(gpu_driver_vendors)
      ;;
    25) MANIFESTS=(audio) ;;
    26) MANIFESTS=(gaming) ;;
    27) MANIFESTS=(printing) ;;
    30) MANIFESTS=(upstream flatpaks) ;;
  esac
}

# Post-run guidance, called by install.sh when the run finishes.
distro_final_notes() {
  local gpu
  for id in "${SELECTED[@]}"; do
    [[ ${id} == 20 ]] || continue
    while IFS= read -r gpu; do
      [[ ${gpu} == nvidia ]] \
        && log_warn 'Reboot after the NVIDIA akmod finishes building. Check it first with: modinfo -F version nvidia'
    done < <(gpu_driver_vendors)
  done
}
