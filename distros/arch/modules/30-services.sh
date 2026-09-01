#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

log_step "Deploying the compressed-swap configuration"
deploy_system_file \
  "${DISTRO_ROOT}/etc/systemd/zram-generator.conf" \
  /etc/systemd/zram-generator.conf
deploy_system_file \
  "${DISTRO_ROOT}/etc/sysctl.d/99-arch-config.conf" \
  /etc/sysctl.d/99-arch-config.conf
as_root systemctl daemon-reload
# dev-zram0.swap is the unit that runs swapon; it Requires= the
# systemd-zram-setup@zram0.service that creates and formats the device, so
# starting the swap unit brings up both. Starting the setup service alone
# creates the device without adding it to the active swap set.
as_root systemctl start dev-zram0.swap
as_root sysctl --load=/etc/sysctl.d/99-arch-config.conf

log_step "Enabling system services"
# paccache.timer prunes the package cache, reflector.timer re-ranks the
# mirrorlist, fwupd-refresh.timer refreshes LVFS metadata and smartd.service
# watches drive health. All four ship with the packages declared in base.txt.
for service in NetworkManager.service bluetooth.service accounts-daemon.service power-profiles-daemon.service fstrim.timer \
  paccache.timer reflector.timer fwupd-refresh.timer smartd.service; do
  as_root systemctl enable --now "${service}" \
    || die "Unable to enable ${service}. Check that the package providing it is installed: run ./install.sh 10 first."
done

log_step "Enabling user-session services"
if systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service
else
  log_warn "The systemd user session is unavailable; PipeWire will start at the next login."
fi

# pkexec delegates authentication to a Polkit agent, which is what gives coding
# agents a graphical prompt instead of a password TTY they cannot use. There is
# no unit to enable for it: polkit-gnome ships no systemd user service, and
# Caelestia's execs.lua starts the agent by absolute path at every Hyprland
# start. hl.exec_cmd failures are silent, so verify the path here rather than
# discovering it at the first authentication prompt.
readonly POLKIT_AGENT=/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
if [[ ! -x ${POLKIT_AGENT} ]]; then
  die "${POLKIT_AGENT} is missing, so no Polkit agent would run and every graphical authentication prompt would silently do nothing. Run ./install.sh 10 to install polkit-gnome."
fi
log_success "The Polkit agent Caelestia starts is in place."

# These units belong to deselectable packages, so each is enabled only where
# its package survived the package picker. Docker has to be running before
# WinBoat will start: it calls `docker ps` at launch and reports the host as
# unusable when that fails. Tailscale does nothing until tailscaled runs; the
# daemon starts logged out, and `tailscale up` stays a deliberate, interactive
# step because it authenticates this machine against your tailnet.
log_step "Enabling services for the optional package groups"
for service in docker.service tailscaled.service; do
  enable_optional_unit "${service}"
done

ensure_user_in_group gamemode || true
# WinBoat checks `id -Gn` for docker and refuses to run without it. Membership
# is root-equivalent on this machine -- anyone in the docker group can start a
# privileged container -- so it is granted here only because WinBoat requires
# it, and only when Docker was actually installed.
ensure_user_in_group docker || true

# WinBoat boots a real Windows VM inside its container, which needs KVM. The
# firmware switch for it is outside this installer, so report it rather than
# letting the first launch fail with an unexplained container error.
if pacman -Q winboat-bin >/dev/null 2>&1 && [[ ! -e /dev/kvm ]]; then
  log_warn "WinBoat is installed but /dev/kvm is missing; enable virtualization (VT-x or AMD-V) in firmware or its Windows VM cannot boot."
fi

log_success "Services enabled."
