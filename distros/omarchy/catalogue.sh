#!/usr/bin/env bash
# Omarchy catalogue: everything the engine needs to know about this distro.
# Sourced by install.sh after DISTRO_ID/DISTRO_ROOT are resolved.

DISTRO_INFO='Omarchy - Hyprland - Quickshell (desktop preinstalled)'

MODULE_IDS=(10 20)
MODULE_NAMES=(
  'Packages'
  'Fish shell'
)
MODULE_HINTS=(
  'Applications from the official repositories and the AUR'
  'The Arch shell toolchain and the managed fish configuration'
)

# Steps that elevate; matches the privileged operations inside each module.
ROOT_MODULES=(10 20)

declare -A MANIFEST_LABELS=(
  [apps]='Applications'
  [aur]='AUR applications'
  [shell]='Terminal & shell'
)

# Fill MANIFESTS with the selectable package groups of a step.
step_manifests() {
  local id=$1
  MANIFESTS=()
  case ${id} in
    10) MANIFESTS=(apps aur) ;;
    20) MANIFESTS=(shell) ;;
  esac
}

# Post-run guidance, called by install.sh when the run finishes.
distro_final_notes() {
  log_info 'Omarchy owns the desktop; this setup only added packages and the fish configuration. Restart the terminal to load it.'
}
