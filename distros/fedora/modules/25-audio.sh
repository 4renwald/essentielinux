#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

log_step 'Installing audio packages'
install_dnf_manifest "${DISTRO_ROOT}/packages/audio.txt"

log_step 'Enabling PipeWire user services'
if systemctl --user show-environment >/dev/null 2>&1; then
  user_units=(pipewire.socket pipewire-pulse.socket wireplumber.service)
  # mpris-proxy.service ships with bluez, which is deselectable in core.txt.
  if systemctl --user list-unit-files mpris-proxy.service 2>/dev/null | grep -q '^mpris-proxy\.service'; then
    user_units+=(mpris-proxy.service)
  else
    log_warn 'mpris-proxy.service is not available; Bluetooth media controls are skipped.'
  fi
  systemctl --user enable --now "${user_units[@]}"
else
  log_warn 'No systemd user manager is reachable; audio services will activate at the next login.'
fi

log_success 'PipeWire, WirePlumber, and Bluetooth audio codecs are configured.'
