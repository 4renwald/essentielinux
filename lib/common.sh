#!/usr/bin/env bash

if [[ -n ${WORKSTATION_COMMON_LOADED:-} ]]; then
  return 0
fi
readonly WORKSTATION_COMMON_LOADED=1

if [[ -t 1 ]]; then
  readonly C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_DIM=$'\e[2m'
  readonly C_CYAN=$'\e[1;36m' C_GREEN=$'\e[1;32m' C_YELLOW=$'\e[1;33m' C_RED=$'\e[1;31m' C_MAGENTA=$'\e[1;35m'
else
  readonly C_RESET='' C_BOLD='' C_DIM='' C_CYAN='' C_GREEN='' C_YELLOW='' C_RED='' C_MAGENTA=''
fi

log_step() { printf '\n%s[*]%s %s%s\n' "${C_CYAN}" "${C_RESET}" "${C_BOLD}" "$*${C_RESET}"; }
log_success() { printf '%s[+]%s %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
log_info() { printf '%s[i]%s %s\n' "${C_DIM}" "${C_RESET}" "$*"; }
log_warn() { printf '%s[!]%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
log_error() { printf '%s[x]%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; }
die() { log_error "$*"; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command is missing: $1"
}

# GPU ---------------------------------------------------------------------------

# Valid vendor selectors. `none` covers VMs and headless machines.
valid_gpu_vendor() {
  case $1 in
    nvidia | amd | intel | none) return 0 ;;
    *) return 1 ;;
  esac
}

readonly NVIDIA_NOOPEN_PCI_IDS_FILE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/data/nvidia-noopen-pciids.txt"

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
  done < <(
    lspci -n 2>/dev/null \
      | awk '$2 ~ /^03/ { split(tolower($3), id, ":"); print id[1] }' \
      | sort -u
  )
}

# Resolve the driver stacks to install. By default every detected display
# vendor is included, which covers hybrid Intel/AMD + NVIDIA laptops. The
# optional override is only for exceptional setups and testing.
gpu_driver_vendors() {
  local forced="${WORKSTATION_GPU:-}"
  if [[ -n ${forced} ]]; then
    if valid_gpu_vendor "${forced}"; then
      [[ ${forced} == none ]] || printf '%s\n' "${forced}"
      return 0
    fi
    die "Invalid WORKSTATION_GPU '${forced}'. Use nvidia, amd, intel, or none."
  fi
  gpu_hardware_vendors
}

# List the PCI IDs of NVIDIA display controllers, not their audio functions.
nvidia_display_pci_ids() {
  require_command lspci
  lspci -n 2>/dev/null \
    | awk '$2 ~ /^03/ && tolower($3) ~ /^10de:/ { print tolower($3) }' \
    | sort -u
}

# NVIDIA's open kernel modules need Turing or newer. The PCI-ID list comes
# from RPM Fusion's maintained NVIDIA package data, the same data its normal
# akmod package uses for this decision. IDs older than Turing but absent from
# that current-driver list need a historical driver branch, so report them as
# unsupported instead of guessing. Return proprietary if any detected NVIDIA
# display controller needs the closed module, open for Turing or newer, or
# unsupported when only a historical driver branch may work.
nvidia_kernel_module_flavor_for_ids() {
  (($# > 0)) || return 1
  [[ -r ${NVIDIA_NOOPEN_PCI_IDS_FILE} ]] \
    || die "Missing NVIDIA PCI-ID data: ${NVIDIA_NOOPEN_PCI_IDS_FILE}"
  local id device
  for id in "$@"; do
    if grep -Fxiq -- "${id}" "${NVIDIA_NOOPEN_PCI_IDS_FILE}"; then
      printf '%s\n' proprietary
      return 0
    fi
    device=${id#*:}
    if [[ ${device} =~ ^[[:xdigit:]]{4}$ ]] && ((16#${device} < 0x1e00)); then
      printf '%s\n' unsupported
      return 0
    fi
  done
  printf '%s\n' open
}

nvidia_kernel_module_flavor() {
  local -a ids=()
  mapfile -t ids < <(nvidia_display_pci_ids)
  ((${#ids[@]} > 0)) || return 1
  nvidia_kernel_module_flavor_for_ids "${ids[@]}"
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
  # Every branch propagates the command's own status: callers branch on
  # `if as_root test ...`, and a forced 0 would turn every existence check
  # into a true answer.
  if ((EUID == 0)); then
    "$@"
    return
  fi
  case ${ELEVATION_MODE:-} in
    root)
      "$@"
      return
      ;;
    sudo)
      sudo -n true 2>/dev/null \
        || { log_warn 'sudo authorization expired; one more password prompt.'; sudo -v; }
      sudo -n -- "$@"
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

# Systemd and group membership ----------------------------------------------------

# True when a unit file with exactly this name is installed. Units belonging to
# deselectable packages are absent on machines where the package was dropped,
# and `systemctl enable` on a missing unit fails the whole step.
systemd_unit_exists() {
  [[ -n $(systemctl list-unit-files --no-legend --no-pager -- "$1" 2>/dev/null) ]]
}

# Enable and start a unit only when the package that ships it was installed.
enable_optional_unit() {
  local unit=$1
  if ! systemd_unit_exists "${unit}"; then
    log_info "${unit} is not installed; skipping it."
    return 0
  fi
  as_root systemctl enable --now "${unit}" \
    || die "Unable to enable ${unit}. Check the package that provides it."
}

# Add the invoking user to a group a package created. Returns non-zero when the
# group does not exist, which means the package providing it was not installed.
ensure_user_in_group() {
  local group=$1 user
  user="$(id -un)"
  getent group "${group}" >/dev/null 2>&1 || return 1
  if id -nG "${user}" | tr ' ' '\n' | grep -Fxq "${group}"; then
    return 0
  fi
  log_step "Adding ${user} to the ${group} group"
  as_root usermod --append --groups "${group}" "${user}"
  log_warn "${user} joined the ${group} group; it takes effect at the next login."
}

# Package selection store -------------------------------------------------------
#
# Manifest lines use the format `name :: description`; a leading `*` marks a
# structural package that cannot be deselected. Only *deselected* packages are
# kept in exported variables for this setup run, so child module processes see
# the same choices without leaving state on the machine.

# Selection keys are manifest basenames without directory or extension, so the
# interactive picker (which holds bare names) and modules (which hold manifest
# paths) resolve the same exported, per-run selection variable.
selection_key() {
  local name=${1##*/}
  printf '%s\n' "${name%.txt}"
}

selection_variable() {
  local key
  key="$(selection_key "$1")"
  key=${key^^}
  key=${key//[![:alnum:]_]/_}
  printf 'WORKSTATION_SKIP_%s\n' "${key}"
}

selection_load_skip() {
  SKIP_ITEMS=()
  local variable values
  variable="$(selection_variable "$1")"
  values=${!variable:-}
  [[ -n ${values} ]] || return 0
  mapfile -t SKIP_ITEMS < <(printf '%s' "${values}")
}

selection_is_skipped() {
  local manifest=$1 name=$2 variable values item
  variable="$(selection_variable "${manifest}")"
  values=${!variable:-}
  [[ -n ${values} ]] || return 1
  while IFS= read -r item; do
    [[ ${item} == "${name}" ]] && return 0
  done <<< "${values}"
  return 1
}

# Export the deselected list for a manifest. Modules inherit it from the
# interactive installer, but it vanishes when that one setup run exits.
selection_save_skip() {
  local manifest=$1
  shift
  local variable values='' item
  variable="$(selection_variable "${manifest}")"
  if (($# > 0)); then
    for item in "$@"; do
      values+="${item}"$'\n'
    done
    export "${variable}=${values}"
  else
    unset "${variable}"
  fi
}

# Number of deselected packages in this run, for menu display.
selection_count_skip() {
  selection_load_skip "$1"
  printf '%s\n' "${#SKIP_ITEMS[@]}"
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
