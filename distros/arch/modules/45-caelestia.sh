#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

require_command caelestia
require_command paru
require_command jq
require_command git
require_command Hyprland
require_command vercmp
require_command patch

readonly CAELESTIA_STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/caelestia"
readonly CAELESTIA_STATE_FILE="${CAELESTIA_STATE_DIR}/dots-state.json"
readonly CAELESTIA_DOTS_DIR="${CAELESTIA_STATE_DIR}/dots"
readonly CAELESTIA_EXECS_PATCH="${DISTRO_ROOT}/etc/caelestia/execs-night-light.patch"
readonly HYPR_CONFIG_DIR="${HOME}/.config/hypr"
readonly FISH_CONFIG="${HOME}/.config/fish/config.fish"
readonly WALLPAPER_REPOSITORY='https://github.com/dharmx/walls.git'
readonly WALLPAPER_DIR="${HOME}/Pictures/Wallpapers"

# The categories you actually keep. Only these are downloaded. The rest of
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
# Caelestia ships no per-terminal colour files. Its shell writes the active
# scheme to this file as escape sequences, and its fish config replays them at
# every interactive start, which is what themes the terminal.
readonly CAELESTIA_SEQUENCES_PATTERN='caelestia/sequences.txt'

readonly HYPR_MAIN_CONFIG="${HYPR_CONFIG_DIR}/hyprland.lua"
readonly HYPR_EXECS_CONFIG="${HYPR_CONFIG_DIR}/hyprland/execs.lua"
readonly HYPR_EXECS_REQUIRE_PATTERN="require[[:space:]]*\\([[:space:]]*['\"]hyprland\\.execs['\"][[:space:]]*\\)"
readonly HYPR_START_EVENT_PATTERN="hl\\.on[[:space:]]*\\([[:space:]]*['\"]hyprland\\.start['\"]"
readonly CAELESTIA_AUTOSTART_PATTERN="hl\\.exec_cmd[[:space:]]*\\([[:space:]]*['\"]caelestia[[:space:]]+shell[[:space:]]+-d['\"][[:space:]]*\\)"

[[ -r ${CAELESTIA_EXECS_PATCH} ]] || die "Missing Caelestia override: ${CAELESTIA_EXECS_PATCH}"

render_expected_hypr_file() {
  local source_file=$1 relative_file=$2 output_file=$3

  cp -- "${source_file}" "${output_file}"
  if [[ ${relative_file} == hyprland/execs.lua ]]; then
    patch --silent --fuzz=0 --no-backup-if-mismatch "${output_file}" "${CAELESTIA_EXECS_PATCH}" \
      || die "Caelestia changed hyprland/execs.lua; refresh ${CAELESTIA_EXECS_PATCH} before deploying it."
  fi
}

deployed_hypr_file_matches() {
  local source_file=$1 relative_file=$2 target_file=$3 expected_file

  if [[ ${relative_file} != hyprland/execs.lua ]]; then
    cmp -s -- "${source_file}" "${target_file}"
    return
  fi

  expected_file="$(mktemp "${TMPDIR:-/tmp}/workstation-caelestia-expected-XXXXXX")"
  render_expected_hypr_file "${source_file}" "${relative_file}" "${expected_file}"
  local status=0
  cmp -s -- "${expected_file}" "${target_file}" || status=$?
  rm -f -- "${expected_file}"
  return "${status}"
}

apply_caelestia_overrides() {
  local source_file="${CAELESTIA_DOTS_DIR}/hypr/hyprland/execs.lua"
  local target_file="${HYPR_EXECS_CONFIG}" expected_file

  [[ -f ${source_file} && -f ${target_file} ]] || return 1
  expected_file="$(mktemp "${TMPDIR:-/tmp}/workstation-caelestia-execs-XXXXXX")"
  render_expected_hypr_file "${source_file}" hyprland/execs.lua "${expected_file}"

  if cmp -s -- "${expected_file}" "${target_file}"; then
    rm -f -- "${expected_file}"
    return 0
  fi
  if ! cmp -s -- "${source_file}" "${target_file}"; then
    rm -f -- "${expected_file}"
    return 1
  fi

  install --mode=0644 "${expected_file}" "${target_file}"
  rm -f -- "${expected_file}"
  log_success "Made Caelestia's automatic night light controllable through hypr-vars.lua."
}

hyprland_version="$(pacman -Q hyprland 2>/dev/null | awk 'NF >= 2 { print $2; exit }')" || hyprland_version=''
if [[ -z ${hyprland_version} || $(vercmp "${hyprland_version}" 0.55.0) -lt 0 ]]; then
  die "Caelestia's native Lua config requires Hyprland 0.55 or newer; installed version: ${hyprland_version:-missing}. Run ./install.sh 00 and ./install.sh 10 first."
fi

caelestia_deployed_tree_complete() {
  local applied_rev relative_file source_file source_rev target_file
  local found_file=false

  [[ -d ${CAELESTIA_DOTS_DIR}/.git ]] || return 1
  applied_rev="$(jq -er '.applied_rev | select(type == "string" and length > 0)' "${CAELESTIA_STATE_FILE}" 2>/dev/null)" \
    || return 1
  source_rev="$(git -C "${CAELESTIA_DOTS_DIR}" rev-parse HEAD 2>/dev/null)" || return 1
  [[ ${source_rev} == "${applied_rev}" && -d ${CAELESTIA_DOTS_DIR}/hypr ]] || return 1

  if find "${CAELESTIA_DOTS_DIR}/hypr" -mindepth 1 ! -type d ! -type f -print -quit | grep -q .; then
    return 1
  fi

  while IFS= read -r -d '' source_file; do
    found_file=true
    relative_file="${source_file#"${CAELESTIA_DOTS_DIR}"/hypr/}"
    target_file="${HYPR_CONFIG_DIR}/${relative_file}"
    [[ -f ${target_file} ]] || return 1
    ! path_has_symlink "${target_file}" || return 1
    deployed_hypr_file_matches "${source_file}" "${relative_file}" "${target_file}" || return 1
  done < <(find "${CAELESTIA_DOTS_DIR}/hypr" -type f -print0)

  [[ ${found_file} == true ]]
}

caelestia_config_complete() {
  command -v qs >/dev/null 2>&1 || return 1
  pacman -Q caelestia-shell >/dev/null 2>&1 || return 1

  [[ -f ${CAELESTIA_STATE_FILE} ]] || return 1
  jq -e '
    (.applied_rev | type == "string" and length > 0)
    and (.enabled_components | type == "array" and index("hypr") != null)
    and (.enabled_components | index("fish") != null)
  ' "${CAELESTIA_STATE_FILE}" >/dev/null 2>&1 || return 1

  # Without the fish component nothing replays the scheme, so every terminal
  # keeps its own default palette.
  [[ -f ${FISH_CONFIG} ]] || return 1
  grep -Fq "${CAELESTIA_SEQUENCES_PATTERN}" "${FISH_CONFIG}" || return 1

  caelestia_deployed_tree_complete || return 1
  ! find "${HYPR_CONFIG_DIR}" -type l -print -quit | grep -q . || return 1

  grep -Eq "${HYPR_EXECS_REQUIRE_PATTERN}" "${HYPR_MAIN_CONFIG}" || return 1
  grep -Eq "${HYPR_START_EVENT_PATTERN}" "${HYPR_EXECS_CONFIG}" || return 1
  grep -Eq "${CAELESTIA_AUTOSTART_PATTERN}" "${HYPR_EXECS_CONFIG}" || return 1
  Hyprland --verify-config --config "${HYPR_MAIN_CONFIG}" >/dev/null 2>&1
}

wallpaper_repository_matches() {
  local origin_url

  origin_url="$(git -C "${WALLPAPER_DIR}" remote get-url origin 2>/dev/null)" || return 1
  [[ ${origin_url%.git} == ${WALLPAPER_REPOSITORY%.git} ]]
}

apply_wallpaper_selection() {
  ((${#WALLPAPER_KEPT_CATEGORIES[@]} > 0)) \
    || die 'The wallpaper keep list is empty; nothing to select.'
  git -C "${WALLPAPER_DIR}" sparse-checkout set "${WALLPAPER_KEPT_CATEGORIES[@]}"
}

install_wallpaper_repository() {
  if [[ -d ${WALLPAPER_DIR}/.git ]]; then
    if wallpaper_repository_matches; then
      git -C "${WALLPAPER_DIR}" pull --ff-only
      apply_wallpaper_selection
      log_success "Wallpapers updated at ${WALLPAPER_DIR}."
    else
      log_warn "${WALLPAPER_DIR} is a different repository; leaving it untouched."
    fi
  elif [[ -e ${WALLPAPER_DIR} || -L ${WALLPAPER_DIR} ]]; then
    log_warn "${WALLPAPER_DIR} already exists and is not a Git checkout; leaving it untouched."
  else
    if path_has_symlink "${HOME}/Pictures"; then
      die "Refusing to clone wallpapers through a symlinked directory: ${HOME}/Pictures"
    fi

    log_step "Cloning wallpapers for Caelestia"
    install -d "${HOME}/Pictures"
    git clone --depth 1 --filter=blob:none --sparse \
      "${WALLPAPER_REPOSITORY}" "${WALLPAPER_DIR}"
    apply_wallpaper_selection
    log_success "Wallpapers cloned to ${WALLPAPER_DIR}."
  fi
}

# Apply the local startup guard before unrelated wallpaper validation so an
# existing user-managed Wallpapers directory cannot re-enable night light.
apply_caelestia_overrides || true
install_wallpaper_repository

if caelestia_config_complete; then
  log_success "The complete Caelestia configuration matches its applied revision plus managed overrides and passes Hyprland's verifier."
  exit 0
fi

# Quickshell is pulled in as a normal dependency of caelestia-shell by the
# Caelestia installer; on Arch nothing else provides or overrides it.

# The Caelestia installer reads its prompts from stdin and aborts silently on
# end of input (for example when the installation was started through
# `curl | bash`). Attach it to the terminal explicitly.
{ : < /dev/tty; } 2>/dev/null || die "The Caelestia installer is interactive and needs a terminal. Run ./install.sh 45 from a terminal session."

log_step "Running the Caelestia dotfiles installer"
log_warn "This step is interactive: answer the prompts. Building Quickshell takes a while."
# Passing any component flag makes the installer skip its component prompt and
# take the manifest defaults instead, so the component set stops depending on
# how the prompt was answered. That matters because the deployed Hyprland
# config executes what those components install (gnome-keyring, polkit-gnome,
# trash-cli, the GTK and Qt theming) and hl.exec_cmd failures are silent.
# firefox is the one default turned off here: this system uses Zen.
#
# Older caelestia-cli releases have no component flags, so fall back to the
# interactive form rather than dying on an argument error.
if caelestia install --help 2>&1 | grep -Fq -- '--disable-components'; then
  caelestia install --disable-components firefox < /dev/tty
else
  log_warn "This caelestia-cli has no component flags; the installer will ask instead."
  log_warn "Select at least 'hypr', 'fish', 'gtk', 'qt', 'auth', 'fonts' and 'tools': the deployed config runs what they install."
  caelestia install < /dev/tty
fi

apply_caelestia_overrides \
  || die "Unable to apply the managed Caelestia night-light override after installation."

if ! caelestia_config_complete; then
  if [[ -f ${HYPR_MAIN_CONFIG} ]]; then
    verify_output="$(Hyprland --verify-config --config "${HYPR_MAIN_CONFIG}" 2>&1)" || true
    [[ -z ${verify_output} ]] || log_error "Hyprland config verification output: ${verify_output//$'\n'/; }"
  fi
  die "The Caelestia installer exited without a complete managed copy of its Hyprland tree, its fish component, required packages, valid saved state, or a Hyprland-verifiable shell startup callback. Review the installer and verification output."
fi

log_success "Caelestia's complete Hyprland tree matches the applied upstream revision plus managed overrides and passes Hyprland's config verifier."
