#!/usr/bin/env bash

if [[ -n ${WORKSTATION_COMMON_LOADED:-} ]]; then
  return 0
fi
readonly WORKSTATION_COMMON_LOADED=1

if [[ -t 1 ]]; then
  readonly C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_DIM=$'\e[2m'
  readonly C_CYAN=$'\e[1;36m' C_GREEN=$'\e[1;32m' C_YELLOW=$'\e[1;33m' C_RED=$'\e[1;31m'
else
  readonly C_RESET='' C_BOLD='' C_DIM='' C_CYAN='' C_GREEN='' C_YELLOW='' C_RED=''
fi

log_step() { printf '\n%s▸%s %s\n' "${C_CYAN}" "${C_RESET}" "${C_BOLD}$*${C_RESET}"; }
log_success() { printf '%s  ✔  %s%s\n' "${C_GREEN}" "$*${C_RESET}"; }
log_info() { printf '%s  ·  %s%s\n' "${C_DIM}" "$*${C_RESET}"; }
log_warn() { printf '%s  !  %s%s\n' "${C_YELLOW}" "$*${C_RESET}" >&2; }
log_error() { printf '%s  ✖  %s%s\n' "${C_RED}" "$*${C_RESET}" >&2; }
die() { log_error "$*"; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command is missing: $1"
}

# Distro ------------------------------------------------------------------------
#
# DISTRO_ID is set by install.sh before the distro catalogue is sourced.
# Modules run as standalone processes and resolve it lazily here instead.

supported_distro() {
  case $1 in
    fedora | arch) return 0 ;;
    *) return 1 ;;
  esac
}

current_distro() {
  if [[ -n ${DISTRO_ID:-} ]]; then
    printf '%s\n' "${DISTRO_ID}"
    return 0
  fi
  [[ -r /etc/os-release ]] || die 'Unable to identify the operating system.'
  local id
  id="$(bash -c '. /etc/os-release 2>/dev/null; printf %s "${ID:-}"')"
  supported_distro "${id}" || die "workstation supports Fedora and Arch Linux; found '${id:-unknown}'."
  printf '%s\n' "${id}"
}

# GPU ---------------------------------------------------------------------------

# Valid vendor selectors. `none` covers VMs and headless machines.
valid_gpu_vendor() {
  case $1 in
    nvidia | amd | intel | none) return 0 ;;
    *) return 1 ;;
  esac
}

gpu_state_file() {
  printf '%s/workstation/%s/gpu\n' "${XDG_STATE_HOME:-${HOME}/.local/state}" "$(current_distro)"
}

# Print the GPU vendors physically present, one per line. Empty on VMs.
gpu_hardware_vendors() {
  command -v lspci >/dev/null 2>&1 || return 0
  local id
  while IFS= read -r id; do
    case ${id} in
      10de) echo nvidia ;;
      1002) echo amd ;;
      8086) echo intel ;;
    esac
  done < <(lspci -nmm -d ::0300,::0302,::0380 2>/dev/null | awk -F'"' '{print $2}' | sort -u)
}

# Resolve the effective GPU vendor: WORKSTATION_GPU env, then the saved
# choice from a previous interactive run, then single-GPU auto-detection.
# Returns 1 when nothing can be resolved.
gpu_vendor() {
  local forced="${WORKSTATION_GPU:-}" saved
  if [[ -n ${forced} ]]; then
    if valid_gpu_vendor "${forced}"; then
      printf '%s\n' "${forced}"
      return 0
    fi
    die "Invalid WORKSTATION_GPU '${forced}'. Use nvidia, amd, intel, or none."
  fi
  saved="$(cat -- "$(gpu_state_file)" 2>/dev/null || true)"
  if valid_gpu_vendor "${saved}"; then
    printf '%s\n' "${saved}"
    return 0
  fi
  local -a hardware=()
  mapfile -t hardware < <(gpu_hardware_vendors)
  if ((${#hardware[@]} == 1)); then
    printf '%s\n' "${hardware[0]}"
    return 0
  fi
  return 1
}

# Elevation ----------------------------------------------------------------------
#
# The installer asks for the password exactly once: `sudo -v` caches the
# credentials for the terminal session and a background refresher keeps the
# timestamp alive during long downloads. Every privileged call then runs
# through `sudo -n`. If sudo is unavailable or declined, the installer falls
# back to per-operation pkexec prompts.
ELEVATION_MODE=''
elevation_refresher_pid=''

start_elevation_refresher() {
  (
    while sleep 240; do
      sudo -n -v 2>/dev/null || exit 0
    done
  ) >/dev/null 2>&1 &
  elevation_refresher_pid=$!
}

# Resolve the elevation strategy up front so the user is prompted once, before
# any module runs.
begin_elevation() {
  if ((EUID == 0)); then
    ELEVATION_MODE=root
    return 0
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    ELEVATION_MODE=pkexec
    return 0
  fi
  if sudo -n true 2>/dev/null; then
    ELEVATION_MODE=sudo
  else
    log_info 'sudo will ask for your password once; it covers the whole setup.'
    if sudo -v; then
      ELEVATION_MODE=sudo
      start_elevation_refresher
    else
      log_warn 'sudo was declined; falling back to per-operation pkexec prompts.'
      ELEVATION_MODE=pkexec
    fi
  fi
  export ELEVATION_MODE
}

end_elevation() {
  if [[ -n ${elevation_refresher_pid} ]]; then
    pkill -P "${elevation_refresher_pid}" 2>/dev/null || true
    kill "${elevation_refresher_pid}" 2>/dev/null || true
    wait "${elevation_refresher_pid}" 2>/dev/null || true
    elevation_refresher_pid=''
  fi
}

as_root() {
  if ((EUID == 0)); then
    "$@"
    return 0
  fi
  case ${ELEVATION_MODE:-} in
    root)
      "$@"
      return 0
      ;;
    sudo)
      sudo -n true 2>/dev/null \
        || { log_warn 'sudo authorization expired; one more password prompt.'; sudo -v; }
      sudo -n -- "$@"
      # Propagate the command's own status: callers branch on `if as_root test`
      # and a forced 0 would skip existence checks (and the Bibata install).
      return
      ;;
  esac
  # Lazy resolution for module runs that skip the installer preamble.
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    ELEVATION_MODE=sudo
    export ELEVATION_MODE
    sudo -n -- "$@"
  elif command -v sudo >/dev/null 2>&1 && { [[ -t 0 ]] || [[ -n ${SUDO_ASKPASS:-} ]]; }; then
    ELEVATION_MODE=sudo
    export ELEVATION_MODE
    sudo -v
    sudo -n -- "$@"
  else
    ELEVATION_MODE=pkexec
    export ELEVATION_MODE
    require_command pkexec
    pkexec "$@"
  fi
}

# Package selection store -------------------------------------------------------
#
# Manifest lines use the format `name :: description`; a leading `*` marks a
# structural package that cannot be deselected. Only *deselected* packages are
# persisted (one `.skip` file per manifest), so packages added to the repository
# later are installed by default and per-machine choices stay small diffs.

selections_dir() {
  printf '%s/workstation/%s/selections\n' "${XDG_STATE_HOME:-${HOME}/.local/state}" "$(current_distro)"
}

# Selection keys are manifest basenames without directory or extension, so the
# interactive picker (which holds bare names) and modules (which hold manifest
# paths) resolve the same skip file.
selection_key() {
  local name=${1##*/}
  printf '%s\n' "${name%.txt}"
}

selection_skip_file() {
  printf '%s/%s.skip\n' "$(selections_dir)" "$(selection_key "$1")"
}

selection_load_skip() {
  SKIP_ITEMS=()
  local file
  file="$(selection_skip_file "$1")"
  [[ -r ${file} ]] || return 0
  mapfile -t SKIP_ITEMS < <(grep -v '^[[:space:]]*$' "${file}" 2>/dev/null || true)
}

selection_is_skipped() {
  local manifest=$1 name=$2 file
  file="$(selection_skip_file "${manifest}")"
  [[ -r ${file} ]] || return 1
  grep -Fxq -- "${name}" "${file}"
}

# Save the deselected list for a manifest (empty arguments list = nothing deselected).
selection_save_skip() {
  local manifest=$1
  shift
  local file
  file="$(selection_skip_file "${manifest}")"
  mkdir -p -- "$(dirname -- "${file}")"
  if (($# > 0)); then
    printf '%s\n' "$@" >"${file}"
  else
    : >"${file}"
  fi
}

# Remove a manifest's customization entirely.
selection_clear() {
  rm -f -- "$(selection_skip_file "$1")"
}

# Number of deselected packages recorded for a manifest, for menu display.
selection_count_skip() {
  local file count=0
  file="$(selection_skip_file "$1")"
  if [[ -r ${file} ]]; then
    count="$(grep -c . -- "${file}" 2>/dev/null || true)"
  fi
  printf '%s\n' "${count:-0}"
}

# Parse a manifest into PACKAGES / PACKAGE_DESCRIPTIONS / PACKAGE_REQUIRED.
read_manifest() {
  local manifest=$1 line name desc required
  PACKAGES=()
  PACKAGE_DESCRIPTIONS=()
  PACKAGE_REQUIRED=()
  [[ -r ${manifest} ]] || die "Missing manifest: ${manifest}"
  while IFS= read -r line || [[ -n ${line} ]]; do
    line=${line%%#*}
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [[ -n ${line} ]] || continue
    name=${line}
    desc=''
    if [[ ${line} == *' :: '* ]]; then
      name=${line%% :: *}
      desc=${line#* :: }
      desc=${desc#"${desc%%[![:space:]]*}"}
      desc=${desc%"${desc##*[![:space:]]}"}
    fi
    name=${name#"${name%%[![:space:]]*}"}
    name=${name%"${name##*[![:space:]]}"}
    required=0
    if [[ ${name} == \** ]]; then
      required=1
      name=${name#\*}
    fi
    PACKAGES+=("${name}")
    PACKAGE_DESCRIPTIONS+=("${desc}")
    PACKAGE_REQUIRED+=("${required}")
  done <"${manifest}"
}

# Drop deselected packages from the arrays read_manifest filled, keeping all
# three arrays aligned.
apply_selection() {
  local manifest=$1 index
  selection_load_skip "${manifest}"
  ((${#SKIP_ITEMS[@]} > 0)) || return 0
  local -a keep_p=() keep_d=() keep_r=()
  for ((index = 0; index < ${#PACKAGES[@]}; index++)); do
    if ! selection_is_skipped "${manifest}" "${PACKAGES[index]}"; then
      keep_p+=("${PACKAGES[index]}")
      keep_d+=("${PACKAGE_DESCRIPTIONS[index]}")
      keep_r+=("${PACKAGE_REQUIRED[index]}")
    fi
  done
  PACKAGES=("${keep_p[@]}")
  PACKAGE_DESCRIPTIONS=("${keep_d[@]}")
  PACKAGE_REQUIRED=("${keep_r[@]}")
}

# Package installers --------------------------------------------------------------
#
# One per package manager. Each reads a manifest, applies the per-machine
# selection, and installs what survives.

install_dnf_manifest() {
  local manifest=$1
  read_manifest "${manifest}"
  apply_selection "${manifest}"
  if ((${#PACKAGES[@]} == 0)); then
    log_info "No packages selected in $(basename -- "${manifest}"); skipping."
    return 0
  fi
  as_root dnf -y install "${PACKAGES[@]}"
}

install_pacman_manifest() {
  local manifest=$1
  read_manifest "${manifest}"
  apply_selection "${manifest}"
  if ((${#PACKAGES[@]} == 0)); then
    log_info "No packages selected in $(basename -- "${manifest}"); skipping."
    return 0
  fi
  as_root pacman -S --needed --noconfirm "${PACKAGES[@]}"
}

# AUR packages remain user-produced PKGBUILDs: they build unprivileged through
# paru, which asks for sudo itself when the built package is installed.
install_paru_manifest() {
  local manifest=$1
  read_manifest "${manifest}"
  apply_selection "${manifest}"
  if ((${#PACKAGES[@]} == 0)); then
    log_info "No AUR packages selected in $(basename -- "${manifest}"); skipping."
    return 0
  fi
  require_command paru
  log_warn 'AUR PKGBUILDs are user-produced. Review the changes shown by paru before approving installation.'
  paru -S --aur --needed "${PACKAGES[@]}"
}

# System file deployment ----------------------------------------------------------

path_has_symlink() {
  local path=$1
  while [[ ${path} != "${HOME}" && ${path} != / ]]; do
    [[ ! -L ${path} ]] || return 0
    path="$(dirname -- "${path}")"
  done
  return 1
}

backup_system_file() {
  local target=$1 backup="${target}.workstation-backup"
  if as_root test -e "${target}" && ! as_root test -e "${backup}"; then
    as_root cp --archive -- "${target}" "${backup}"
    log_warn "Preserved the previous file as ${backup}."
  fi
}

deploy_system_file() {
  local source=$1 target=$2 mode=${3:-0644}
  [[ -f ${source} ]] || die "Missing source file: ${source}"
  if path_has_symlink "${target}" || path_has_symlink "$(dirname -- "${target}")"; then
    die "Refusing to deploy a system file through a symlink: ${target}"
  fi
  if as_root test -f "${target}" && cmp -s -- "${source}" "${target}"; then
    return 0
  fi
  backup_system_file "${target}"
  as_root install -D --mode="${mode}" -- "${source}" "${target}"
}

# Downloads ------------------------------------------------------------------------

github_asset_url() {
  local repository=$1 pattern=$2
  curl -fsSL --retry 3 "https://api.github.com/repos/${repository}/releases/latest" \
    | jq -er --arg pattern "${pattern}" \
      '.assets[] | select(.name | test($pattern)) | .browser_download_url' \
    | head -n1
}

download() {
  local url=$1 destination=$2
  curl -fL --retry 3 --retry-delay 2 --output "${destination}" "${url}"
}

require_user() {
  ((EUID != 0)) || die 'Run this installer as the target desktop user. It elevates once via sudo (or pkexec) and never stores your password.'
}
