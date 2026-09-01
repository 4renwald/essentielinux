#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

fedora_release="$(rpm -E %fedora)"
[[ ${fedora_release} =~ ^[0-9]+$ ]] || die "Unable to identify Fedora release: ${fedora_release}"

log_step 'Enabling RPM Fusion Free and Nonfree'
as_root dnf -y install \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_release}.noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_release}.noarch.rpm"

log_step 'Enabling required Fedora and official vendor repositories'
as_root dnf -y install dnf5-plugins flatpak
as_root dnf -y copr enable lionheartp/Hyprland
as_root dnf -y copr enable scottames/ghostty
as_root dnf config-manager addrepo --overwrite \
  --from-repofile='https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo'

deploy_system_file "${DISTRO_ROOT}/etc/yum.repos.d/vscodium.repo" /etc/yum.repos.d/vscodium.repo
deploy_system_file "${DISTRO_ROOT}/etc/yum.repos.d/claude-code.repo" /etc/yum.repos.d/claude-code.repo
as_root dnf config-manager addrepo --overwrite \
  --from-repofile='https://repository.mullvad.net/rpm/stable/mullvad.repo'
# Docker Engine from Docker's own repository, which is what WinBoat's
# documentation requires; Fedora's moby-engine is a different stack and ships
# no Compose v2 plugin under `docker compose`.
as_root dnf config-manager addrepo --overwrite \
  --from-repofile='https://download.docker.com/linux/fedora/docker-ce.repo'
# Tailscale maintains the Fedora packages itself; there is no Fedora build.
as_root dnf config-manager addrepo --overwrite \
  --from-repofile='https://pkgs.tailscale.com/stable/fedora/tailscale.repo'

as_root flatpak remote-add --system --if-not-exists flathub \
  'https://dl.flathub.org/repo/flathub.flatpakrepo'

log_success 'RPM Fusion, Hyprland/Ghostty COPRs, the Brave, Docker and Tailscale repositories, vendor RPM repositories, and Flathub are enabled.'
