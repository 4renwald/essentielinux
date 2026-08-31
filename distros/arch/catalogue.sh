#!/usr/bin/env bash
# Arch catalogue: everything the engine needs to know about this distro.
# Sourced by install.sh after DISTRO_ID/DISTRO_ROOT are resolved.

DISTRO_INFO='Arch · Hyprland · Caelestia'

MODULE_IDS=(00 10 20 25 30 35 40 45 50 52 55)
MODULE_NAMES=(
  'Base system'
  'Packages'
  'GPU drivers'
  'Gaming & AUR'
  'Services'
  'Snapshots'
  'Greeter'
  'Caelestia'
  'Dotfiles'
  'Video pipeline'
  'Limine boot'
)
MODULE_HINTS=(
  'Multilib, pacman options, system update, build tools, and paru'
  'Core, desktop, apps, audio, and shell package groups'
  'CPU microcode and the GPU vendor chosen interactively'
  'Steam, GameMode, Gamescope, and the AUR application set'
  'zram, VM tunables, system services, and user services'
  'btrfs pre-upgrade snapshots through snapper and snap-pac'
  'greetd, the sysc-greet niri session, and the greeter account'
  'Caelestia shell installer, wallpapers, and managed overrides'
  'Copy Hyprland, terminal, and agent configuration into ~'
  'mpv shaders, the ff2mpv host, and Zen decoding preferences'
  'Limine bootloader palette and named firmware entry'
)

# Steps that elevate; matches the privileged operations inside each module.
ROOT_MODULES=(00 10 20 25 30 35 40 55)

declare -A MANIFEST_LABELS=(
  [base]='Core system'
  [desktop]='Desktop & Hyprland'
  [shell]='Terminal & shell'
  [apps]='Applications'
  [audio]='Audio'
  [gaming]='Gaming'
  [aur]='AUR applications'
)

# Fill MANIFESTS with the selectable package groups of a step.
# The GPU step (20) installs by vendor detection at run time, not by manifest,
# so it has no selectable groups; gaming and AUR live together in step 25.
step_manifests() {
  local id=$1
  MANIFESTS=()
  case ${id} in
    10) MANIFESTS=(base desktop apps audio shell) ;;
    25) MANIFESTS=(gaming aur) ;;
  esac
}

# Post-run guidance, called by install.sh when the run finishes.
distro_final_notes() {
  log_info 'Reboot the machine, then run distros/arch/check.sh from a Hyprland session.'
}
