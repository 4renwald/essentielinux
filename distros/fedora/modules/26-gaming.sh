#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

log_step 'Installing gaming packages'
install_dnf_manifest "${DISTRO_ROOT}/packages/gaming.txt"

if ! selection_is_skipped gaming gamemode \
  && getent group gamemode >/dev/null 2>&1 \
  && ! id -nG "$(id -un)" | tr ' ' '\n' | grep -Fxq gamemode; then
  as_root usermod --append --groups gamemode "$(id -un)"
  log_warn 'GameMode group membership takes effect at the next login.'
fi

log_success 'Steam, GameMode, MangoHud, GOverlay, Gamescope, NTSYNC, and Wine are installed.'
