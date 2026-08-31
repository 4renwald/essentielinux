#!/usr/bin/env bash

# Distro-agnostic setup engine. install.sh sources this together with the
# detected distro's catalogue (distros/<id>/catalogue.sh), which supplies:
#   MODULE_IDS / MODULE_NAMES / MODULE_HINTS   the module catalogue
#   MANIFEST_LABELS                           association of manifest → label
#   ROOT_MODULES                              module ids that need elevation
#   DISTRO_INFO                               one-line summary for the banner
#   step_manifests <id>                       fills MANIFESTS for a module id
#   distro_final_notes (optional)             post-run guidance

if [[ -n ${WORKSTATION_ENGINE_LOADED:-} ]]; then
  return 0
fi
readonly WORKSTATION_ENGINE_LOADED=1

# Steps that failed during this run; install.sh turns this into a non-zero
# exit and a summary instead of reporting success over a partial setup.
declare -a FAILED_MODULES=()

# ── Module catalogue ─────────────────────────────────────────────────────────

module_row() {
  local index=$1
  printf '%s  %-19s %s' "${MODULE_IDS[index]}" "${MODULE_NAMES[index]}" "${MODULE_HINTS[index]}"
}

module_index() {
  local wanted=$1 index
  for ((index = 0; index < ${#MODULE_IDS[@]}; index++)); do
    if [[ ${MODULE_IDS[index]} == "${wanted}" ]]; then
      echo "${index}"
      return 0
    fi
  done
  return 1
}

run_module() {
  local id=$1 index file name status
  index="$(module_index "${id}")" || die "No module is numbered ${id}."
  file="$(find "${DISTRO_ROOT}/modules" -maxdepth 1 -type f -name "${id}-*.sh" -print -quit)"
  [[ -n ${file} ]] || die "No module starts with ${id}."
  name=${MODULE_NAMES[index]}
  printf '\n%s╭──── %s  %s%s\n' "${C_CYAN}" "${id}" "${name}" "${C_RESET}"
  if bash "${file}"; then
    printf '%s╰──── %s  %s%s\n' "${C_DIM}" "${id}" "${name}" "${C_RESET}"
    return 0
  else
    # An if without an else reports 0 when its condition fails, so the real
    # module exit status is only visible inside the else branch.
    status=$?
    FAILED_MODULES+=("${id} ${name} (exit ${status})")
    log_error "Step ${id} ${name} failed (exit ${status}); later steps still ran. Resolve the cause before continuing setup."
  fi
}

# ── Package customization ────────────────────────────────────────────────────

# One package group: checkbox menu, applied on enter, cancelled on q.
customize_manifest() {
  local manifest=$1
  local label="${MANIFEST_LABELS[${manifest}]:-${manifest}}"
  read_manifest "${DISTRO_ROOT}/packages/${manifest}.txt"

  local -a checked=() required=() rows=()
  local index row width=0
  for ((index = 0; index < ${#PACKAGES[@]}; index++)); do
    ((${#PACKAGES[index]} > width)) && width=${#PACKAGES[index]}
  done
  for ((index = 0; index < ${#PACKAGES[@]}; index++)); do
    row="$(printf '%-*s' "${width}" "${PACKAGES[index]}")"
    [[ -n ${PACKAGE_DESCRIPTIONS[index]} ]] && row+="  ${PACKAGE_DESCRIPTIONS[index]}"
    ((PACKAGE_REQUIRED[index])) && row+="   · required"
    rows+=("${row}")
    if selection_is_skipped "${manifest}" "${PACKAGES[index]}"; then
      checked+=(0)
    else
      checked+=(1)
    fi
    required+=("${PACKAGE_REQUIRED[index]}")
  done

  local MENU_ON_QUIT=back rc=0
  menu_select_many \
    "📦  ${label}: pick packages" \
    'space toggle · a all/none · r reset · enter apply · q cancel' \
    checked required "${rows[@]}" || rc=$?

  if ((rc == 0)); then
    local -a deselected=()
    for ((index = 0; index < ${#PACKAGES[@]}; index++)); do
      if ((checked[index])) || ((required[index])); then
        continue
      fi
      deselected+=("${PACKAGES[index]}")
    done
    selection_save_skip "${manifest}" "${deselected[@]}"
    log_info "Selected for this run: ${label} ($((${#PACKAGES[@]} - ${#deselected[@]})) of ${#PACKAGES[@]} packages)."
  fi
}

customize_step() {
  local id=$1
  step_manifests "${id}"
  if ((${#MANIFESTS[@]} == 0)); then
    log_info "Step ${id} has no selectable packages."
    return 0
  fi

  local MENU_ON_QUIT=back
  if ((${#MANIFESTS[@]} == 1)); then
    customize_manifest "${MANIFESTS[0]}"
    return 0
  fi

  local index rc=0 choice group_highlight
  while true; do
    local -a group_rows=('← Back')
    for ((index = 0; index < ${#MANIFESTS[@]}; index++)); do
      group_rows+=("${MANIFEST_LABELS[${MANIFESTS[index]}]:-${MANIFESTS[index]}}")
    done
    rc=0
    choice="$(menu_select_one \
      "🧩  Step ${id}: choose a group" \
      '↑/↓ move · enter open · q back' \
      1 \
      "${group_rows[@]}")" || rc=$?
    group_highlight=${MENU_HIGHLIGHT}
    ((rc == 2)) && break
    ((choice == 0)) && break
    MENU_INIT_HIGHLIGHT=${group_highlight}
    customize_manifest "${MANIFESTS[choice - 1]}"
  done
}

# Package customization browser: every selectable group of the distro in one
# menu, whether or not its step is about to run. Opened from the dedicated
# 'Customize packages' row of the module picker.
browse_manifests() {
  local -a keys=() steps_of=()
  local id m index seen
  for id in "${MODULE_IDS[@]}"; do
    step_manifests "${id}"
    for m in "${MANIFESTS[@]}"; do
      seen=false
      for ((index = 0; index < ${#keys[@]}; index++)); do
        if [[ ${keys[index]} == "${m}" ]]; then
          seen=true
          steps_of[index]="${steps_of[index]}, ${id}"
          break
        fi
      done
      if [[ ${seen} == false ]]; then
        keys+=("${m}")
        steps_of+=("${id}")
      fi
    done
  done
  ((${#keys[@]} > 0)) || { log_info 'No selectable package groups.'; return 0; }

  local MENU_ON_QUIT=back rc=0 choice group_highlight
  while true; do
    local -a rows=()
    for ((index = 0; index < ${#keys[@]}; index++)); do
      local label="${MANIFEST_LABELS[${keys[index]}]:-${keys[index]}}"
      rows+=("${label}  (step ${steps_of[index]}; $(selection_count_skip "${keys[index]}") deselected)")
    done
    rc=0
    choice="$(menu_select_one \
      '📦  Package groups: pick one to customize' \
      '↑/↓ move · enter open · q back' \
      1 \
      "${rows[@]}")" || rc=$?
    group_highlight=${MENU_HIGHLIGHT}
    ((rc == 2)) && break
    MENU_INIT_HIGHLIGHT=${group_highlight}
    customize_manifest "${keys[choice]}"
  done
}

# ── Interactive picker ────────────────────────────────────────────────────────

pick_modules_interactively() {
  local -a rows=() required=()
  local index customize_index
  for ((index = 0; index < ${#MODULE_IDS[@]}; index++)); do
    rows+=("$(module_row "${index}")")
    required+=(0)
  done
  # A dedicated, always-visible row that opens the package customization
  # browser instead of running anything. Required-marked so space/all cannot
  # toggle it, and unchecked so the selected count stays honest.
  customize_index=${#rows[@]}
  rows+=('📦  Customize packages: pick per group')
  required+=(1)

  PICK_CHECKED=()
  for ((index = 0; index < ${#MODULE_IDS[@]}; index++)); do
    PICK_CHECKED+=(1)
  done
  PICK_CHECKED+=(0)

  menu_require_tty
  menu_hide_cursor
  trap menu_interrupted INT
  local rc picker_highlight
  while true; do
    rc=0
    menu_select_many \
      '🧩  Which steps should run on this machine?' \
      '↑/↓ move · space toggle · c customize step · enter run · q quit' \
      PICK_CHECKED required "${rows[@]}" || rc=$?
    picker_highlight=${MENU_HIGHLIGHT}
    if ((rc == 3)); then
      if ((picker_highlight < ${#MODULE_IDS[@]})); then
        customize_step "${MODULE_IDS[picker_highlight]}"
      else
        browse_manifests
      fi
      MENU_INIT_HIGHLIGHT=${picker_highlight}
      continue
    fi
    if ((rc == 2)); then
      menu_interrupted
    fi
    if ((picker_highlight == customize_index)); then
      browse_manifests
      MENU_INIT_HIGHLIGHT=${picker_highlight}
      continue
    fi
    break
  done
  menu_show_cursor
  trap - INT

  SELECTED=()
  for ((index = 0; index < ${#MODULE_IDS[@]}; index++)); do
    ((PICK_CHECKED[index])) && SELECTED+=("${MODULE_IDS[index]}")
  done
}

# Validate that every catalogue array lines up. Sourced catalogues call this.
catalogue_check() {
  ((${#MODULE_IDS[@]} > 0)) || die "The ${DISTRO_ID} catalogue declares no modules."
  ((${#MODULE_IDS[@]} == ${#MODULE_NAMES[@]})) \
    || die "The ${DISTRO_ID} catalogue has a MODULE_NAMES/MODULE_IDS length mismatch."
  ((${#MODULE_IDS[@]} == ${#MODULE_HINTS[@]})) \
    || die "The ${DISTRO_ID} catalogue has a MODULE_HINTS/MODULE_IDS length mismatch."
}
