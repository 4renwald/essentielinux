#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# ── Distro detection ─────────────────────────────────────────────────────────
# The whole repository is organized around one question: which supported
# distro is this? Every distro owns its modules, packages, etc, and dotfiles
# under distros/<id>/; only the detection happens here.
detect_distro() {
  [[ -r /etc/os-release ]] || die 'Unable to identify the operating system: /etc/os-release is missing.'
  local id
  id="$(bash -c '. /etc/os-release 2>/dev/null; printf %s "${ID:-}"')"
  [[ -n ${id} ]] || die 'Unable to identify the operating system: /etc/os-release has no ID.'
  printf '%s\n' "${id}"
}

DISTRO_ID="$(detect_distro)"
case ${DISTRO_ID} in
  fedora | arch) ;;
  *) cat >&2 <<EOF
workstation supports Fedora and Arch Linux; /etc/os-release reports '${DISTRO_ID}'.
Support for a new distro lands in distros/${DISTRO_ID}/ with its own catalogue.sh.
EOF
    exit 1
    ;;
esac
readonly DISTRO_ID
readonly DISTRO_ROOT="${REPO_ROOT}/distros/${DISTRO_ID}"

# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/menu.sh
source "${REPO_ROOT}/lib/menu.sh"
# shellcheck source=lib/engine.sh
source "${REPO_ROOT}/lib/engine.sh"
# shellcheck source=distros/fedora/catalogue.sh
# shellcheck source=distros/arch/catalogue.sh
source "${DISTRO_ROOT}/catalogue.sh"
catalogue_check

require_user

# ── Argument parsing ─────────────────────────────────────────────────────────
declare -a args=() SELECTED=() PICK_CHECKED=() MANIFESTS=()
CUSTOMIZE_MODE=''

usage() {
  cat <<'EOF'
Usage: ./install.sh                 Interactive GPU and module picker
       ./install.sh 20 30 35        Run specific module steps
       ./install.sh --list          List the detected distro's modules
       ./install.sh --gpu amd 20    Force a GPU vendor for this run
       ./install.sh --customize     Pick packages per group, run nothing
       ./install.sh --customize=core  Edit one package group directly
       WORKSTATION_GPU=none ./install.sh 20

The installer detects the distro from /etc/os-release (Fedora or Arch), then
loads that distro's modules, manifests, and device-specific steps.

Interactive mode: space toggles steps, enter runs, c customizes the highlighted
step package by package, and the "Customize packages" row at the bottom opens a
browser over every package group. One password prompt covers the whole run;
choices for GPU and deselected packages are remembered per machine and reused
by direct runs. Override the GPU with --gpu or WORKSTATION_GPU
(nvidia, amd, intel, none).
EOF
}

list_modules() {
  local index
  printf '%s modules:\n' "${DISTRO_ID}"
  for ((index = 0; index < ${#MODULE_IDS[@]}; index++)); do
    printf '  %s\n' "$(module_row "${index}")"
  done
}

while (($# > 0)); do
  case $1 in
    --gpu)
      [[ $# -ge 2 ]] || die '--gpu needs a vendor: nvidia, amd, intel, or none.'
      valid_gpu_vendor "$2" || die "Invalid GPU vendor '$2'. Use nvidia, amd, intel, or none."
      WORKSTATION_GPU=$2
      shift 2
      ;;
    --gpu=*)
      valid_gpu_vendor "${1#*=}" || die "Invalid GPU vendor '${1#*=}'. Use nvidia, amd, intel, or none."
      WORKSTATION_GPU=${1#*=}
      shift
      ;;
    --list)
      list_modules
      exit 0
      ;;
    --customize)
      CUSTOMIZE_MODE=browse
      shift
      ;;
    --customize=*)
      CUSTOMIZE_MODE=${1#*=}
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [[ -n ${WORKSTATION_GPU:-} ]]; then
  valid_gpu_vendor "${WORKSTATION_GPU}" \
    || die "Invalid WORKSTATION_GPU '${WORKSTATION_GPU}'. Use nvidia, amd, intel, or none."
fi

menu_banner "${DISTRO_INFO}"

# Package customization without running anything: browse every group, or edit
# one directly. Saved choices apply to later runs of any module that installs
# the group.
if [[ -n ${CUSTOMIZE_MODE} ]]; then
  if [[ ${CUSTOMIZE_MODE} != browse ]]; then
    [[ -r ${DISTRO_ROOT}/packages/${CUSTOMIZE_MODE}.txt ]] \
      || die "No package group named '${CUSTOMIZE_MODE}' exists for ${DISTRO_ID}."
  fi
  menu_require_tty
  if [[ ${CUSTOMIZE_MODE} == browse ]]; then
    browse_manifests
  else
    customize_manifest "${CUSTOMIZE_MODE}"
  fi
  log_success 'Package selections saved; they apply to the next run.'
  exit 0
fi

if ((${#args[@]} == 0)); then
  pick_gpu_interactively
  pick_modules_interactively
  ((${#SELECTED[@]} > 0)) || menu_interrupted
else
  for id in "${args[@]}"; do
    module_index "${id}" || die "No module is numbered ${id}."
  done
  SELECTED=("${args[@]}")
fi

printf '\n%s Running %s setup: %s\n\n' "${C_CYAN}▸${C_RESET}" "${DISTRO_ID}" "${C_BOLD}${SELECTED[*]}${C_RESET}"

# Elevate only if one of the selected steps is privileged.
needs_root=0
for id in "${SELECTED[@]}"; do
  for privileged in "${ROOT_MODULES[@]}"; do
    if [[ ${id} == "${privileged}" ]]; then
      needs_root=1
      break
    fi
  done
done
if ((needs_root)); then
  begin_elevation
fi
trap 'end_elevation' EXIT

for id in "${SELECTED[@]}"; do
  run_module "${id}"
done

log_success "✨ ${DISTRO_ID} setup completed: ${SELECTED[*]}."
# Each distro may define distro_final_notes in its catalogue.
if declare -F distro_final_notes >/dev/null 2>&1; then
  distro_final_notes
fi
