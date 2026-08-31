#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

readonly WALLPAPER_REPOSITORY='https://github.com/4renwald/walls.git'
readonly WALLPAPER_DIR="${HOME}/Pictures/Wallpapers"

log_step 'Installing the managed wallpaper collection'
if [[ -d ${WALLPAPER_DIR}/.git ]]; then
  origin="$(git -C "${WALLPAPER_DIR}" remote get-url origin 2>/dev/null || true)"
  if [[ ${origin%.git} == ${WALLPAPER_REPOSITORY%.git} ]]; then
    git -C "${WALLPAPER_DIR}" pull --ff-only
    log_success "Wallpapers updated at ${WALLPAPER_DIR}."
  else
    log_warn "${WALLPAPER_DIR} is a different repository; leaving it untouched."
  fi
elif [[ -e ${WALLPAPER_DIR} ]]; then
  log_warn "${WALLPAPER_DIR} already exists and is not a Git checkout; leaving it untouched."
else
  install -d "${HOME}/Pictures"
  git clone "${WALLPAPER_REPOSITORY}" "${WALLPAPER_DIR}"
  log_success "Wallpapers cloned to ${WALLPAPER_DIR}."
fi
