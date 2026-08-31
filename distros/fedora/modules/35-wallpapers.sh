#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

readonly WALLPAPER_REPOSITORY='https://github.com/dharmx/walls.git'
readonly WALLPAPER_DIR="${HOME}/Pictures/Wallpapers"

# The categories you actually keep. Only these are downloaded — the rest of
# the upstream repository is never fetched, so the checkout stays small.
readonly -a WALLPAPER_KEPT_CATEGORIES=(
  abstract animated anime apeiros calm centered chillop devicons digital
  dreamcore evangelion gruvbox m-26.jp minimal mountain nature nord outrun
  painting pixel radium spam stalenhag tile unsorted
)

# A private or missing repository must fail loudly instead of sitting at a
# credential prompt in the middle of the setup. GIT_TERMINAL_PROMPT only
# disables terminal prompts: an askpass helper (SSH_ASKPASS or a desktop
# agent picked up through GIT_ASKPASS) would still ask, so point that at
# /bin/true as well; git then gets an empty username and aborts.
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/true

apply_wallpaper_selection() {
  ((${#WALLPAPER_KEPT_CATEGORIES[@]} > 0)) \
    || die 'The wallpaper keep list is empty; nothing to select.'
  git -C "${WALLPAPER_DIR}" sparse-checkout set "${WALLPAPER_KEPT_CATEGORIES[@]}"
}

log_step 'Installing the managed wallpaper collection'
if [[ -d ${WALLPAPER_DIR}/.git ]]; then
  origin="$(git -C "${WALLPAPER_DIR}" remote get-url origin 2>/dev/null || true)"
  if [[ ${origin%.git} == ${WALLPAPER_REPOSITORY%.git} ]]; then
    git -C "${WALLPAPER_DIR}" pull --ff-only
    apply_wallpaper_selection
    log_success "Wallpapers updated at ${WALLPAPER_DIR}."
  else
    log_warn "${WALLPAPER_DIR} is a different repository; leaving it untouched."
  fi
elif [[ -e ${WALLPAPER_DIR} ]]; then
  log_warn "${WALLPAPER_DIR} already exists and is not a Git checkout; leaving it untouched."
else
  if path_has_symlink "${HOME}/Pictures"; then
    die "Refusing to clone wallpapers through a symlinked directory: ${HOME}/Pictures"
  fi

  install -d "${HOME}/Pictures"
  git clone --depth 1 --filter=blob:none --sparse \
    "${WALLPAPER_REPOSITORY}" "${WALLPAPER_DIR}"
  apply_wallpaper_selection
  log_success "Wallpapers cloned to ${WALLPAPER_DIR}."
fi
