#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

log_step 'Deploying zram and virtual-memory policy'
deploy_system_file "${DISTRO_ROOT}/etc/systemd/zram-generator.conf" /etc/systemd/zram-generator.conf
deploy_system_file "${DISTRO_ROOT}/etc/sysctl.d/99-workstation-vm.conf" /etc/sysctl.d/99-workstation-vm.conf
as_root systemctl daemon-reload
if ! swapon --noheadings --show=NAME 2>/dev/null | grep -Fxq /dev/zram0; then
  as_root systemctl start dev-zram0.swap
else
  log_warn 'zram is already active; reboot once after installation to apply the managed size/compression policy.'
fi
as_root sysctl --load=/etc/sysctl.d/99-workstation-vm.conf

log_step 'Enabling required system services'
for service in \
  NetworkManager.service bluetooth.service accounts-daemon.service \
  power-profiles-daemon.service fstrim.timer fwupd-refresh.timer \
  smartd.service; do
  as_root systemctl enable --now "${service}"
done

# These units belong to deselectable packages, so each is enabled only where
# its package survived the package picker. Docker has to be running before
# WinBoat will start: it calls `docker ps` at launch and reports the host as
# unusable when that fails. Tailscale does nothing until tailscaled runs; the
# daemon starts logged out, and `tailscale up` stays a deliberate, interactive
# step because it authenticates this machine against your tailnet.
log_step 'Enabling services for the optional package groups'
for service in docker.service tailscaled.service; do
  enable_optional_unit "${service}"
done

# WinBoat checks `id -Gn` for docker and refuses to run without it. Membership
# is root-equivalent on this machine -- anyone in the docker group can start a
# privileged container -- so it is granted here only because WinBoat requires
# it, and only when Docker Engine was actually installed.
ensure_user_in_group docker || true

# WinBoat boots a real Windows VM inside its container, which needs KVM. The
# firmware switch for it is outside this installer, so report it rather than
# letting the first launch fail with an unexplained container error.
if rpm -q winboat >/dev/null 2>&1 && [[ ! -e /dev/kvm ]]; then
  log_warn 'WinBoat is installed but /dev/kvm is missing; enable virtualization (VT-x or AMD-V) in firmware or its Windows VM cannot boot.'
fi

root_fstype="$(findmnt --noheadings --output FSTYPE --target / | head -n1)"
if [[ ${root_fstype} == btrfs ]]; then
  if ! as_root snapper -c root get-config >/dev/null 2>&1; then
    if as_root test -e /.snapshots; then
      die '/.snapshots already exists without a Snapper root configuration. Inspect it and create the root configuration deliberately before rerunning module 40.'
    fi
    as_root snapper -c root create-config /
  fi
  deploy_system_file \
    "${DISTRO_ROOT}/etc/dnf/libdnf5-plugins/actions.d/90-snapper.actions" \
    /etc/dnf/libdnf5-plugins/actions.d/90-snapper.actions
  as_root systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
else
  log_warn "Root uses ${root_fstype:-an unknown filesystem}; Snapper configuration is skipped."
fi

fish_path="$(command -v fish)" || die 'fish is not installed.'
install_user="$(id -un)"
current_shell="$(getent passwd "${install_user}" | cut -d: -f7)"
if [[ ${current_shell} != "${fish_path}" ]]; then
  as_root chsh -s "${fish_path}" "${install_user}"
  log_warn 'fish becomes the login shell after the next login.'
fi

log_success 'zram, VM tunables, system and optional services, DNF5 snapshots, and the login shell are configured.'
