#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

# Pre-upgrade snapshots are the one thing that turns a bad rolling-release
# update from a reinstall into a rollback. They are a btrfs feature: this
# module detects the root filesystem and does nothing on anything else rather
# than pretending to offer protection it cannot give.

require_command findmnt

root_fstype="$(findmnt --noheadings --output FSTYPE --target / 2>/dev/null)" || root_fstype=''
[[ -n ${root_fstype} ]] || die "Unable to determine the filesystem mounted at /."

if [[ ${root_fstype} != btrfs ]]; then
  log_warn "The root filesystem is ${root_fstype}, not btrfs; automatic pre-upgrade snapshots are unavailable."
  log_warn "XFS has no equivalent. Keep backups of ~ and treat a failed upgrade as a reinstall, or reinstall on btrfs to gain rollback."
  log_success "Snapshot module skipped on ${root_fstype}."
  exit 0
fi

log_step "Installing btrfs snapshot tooling"
# snap-pac is a pacman hook: it needs no service, and it only does anything
# once a snapper configuration named 'root' exists.
as_root pacman -S --needed --noconfirm btrfs-progs snapper snap-pac

if as_root snapper -c root get-config >/dev/null 2>&1; then
  log_success "The snapper 'root' configuration already exists."
else
  # create-config refuses to run when /.snapshots is already a subvolume, which
  # is exactly what several installers leave behind. Moving or deleting an
  # existing subvolume is not something to do unattended under someone's data.
  if [[ -e /.snapshots ]]; then
    die "/.snapshots already exists but no snapper 'root' configuration does. Inspect it, then create the configuration deliberately:
    sudo snapper -c root create-config /
Move /.snapshots aside first if snapper refuses because the subvolume is already present."
  fi

  log_step "Creating the snapper 'root' configuration"
  as_root snapper -c root create-config / \
    || die "snapper could not create a configuration for /. Confirm that / is a btrfs subvolume."
fi

log_step "Enabling snapper timers"
for service in snapper-timeline.timer snapper-cleanup.timer; do
  as_root systemctl enable --now "${service}" \
    || die "Unable to enable ${service}."
done

log_success "Pre-upgrade snapshots are active: snap-pac brackets every pacman transaction."
# Restoring one still needs a bootloader entry that can boot a snapshot, and
# this repository does not manage the bootloader.
log_warn "Snapshots are taken, but booting into one needs bootloader support this repository does not configure."
log_warn "Add it for your bootloader before you need it: list snapshots with 'sudo snapper -c root list'."
