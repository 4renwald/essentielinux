#!/usr/bin/env bash

# Minimal, dependency-free terminal menus: arrow keys, j/k, space to toggle,
# enter to confirm, q to quit. Only usable when stdin is a TTY.
#
# Protocols:
#   menu_select_one  → echoes the chosen index on enter (exit 0); exit 2 on
#                      back (q/esc) when MENU_ON_QUIT=back; aborts otherwise.
#   menu_select_many → mutates the caller's checked array in place; exit 0 on
#                      enter, 2 on back when MENU_ON_QUIT=back, 3 when the
#                      customize key (c) was pressed; aborts otherwise.
#   MENU_LAST_KEY / MENU_HIGHLIGHT are set on every return for the caller.
#   Every return path erases the frame first, so nested menus (the package
#   customization flow) never leave stale copies behind. Callers that redraw
#   a menu in a loop may set MENU_INIT_HIGHLIGHT to the previous
#   MENU_HIGHLIGHT so the cursor comes back where the user left it; the menu
#   consumes (unsets) it after reading.

if [[ -n ${WORKSTATION_MENU_LOADED:-} ]]; then
  return 0
fi
readonly WORKSTATION_MENU_LOADED=1

menu_hide_cursor() { printf '\e[?25l' >&2; }
menu_show_cursor() { printf '\e[?25h' >&2; }

menu_interrupted() {
  menu_show_cursor
  printf '\n%s  ⏹  Setup cancelled.%s\n' "${C_YELLOW}" "${C_RESET}" >&2
  exit 130
}

menu_require_tty() {
  [[ -t 0 ]] || die 'Interactive menus need a terminal. Run module ids directly, e.g. ./install.sh 20 30.'
}

# Print the header: a bold title line over a dim one-line distro summary.
menu_banner() {
  local distro_info=$1
  printf '\n%sessentielinux%s\n' "${C_BOLD}${C_CYAN}" "${C_RESET}" >&2
  printf '\n%s ◆  %s%s\n' "${C_DIM}" "${distro_info}" "${C_RESET}" >&2
  printf '\n' >&2
}

# Render rows, highlighting $2 (0-based). When $3 names an array, prefix
# each row with an [x] / [ ] checkbox; when empty, render single-select style.
_menu_render() {
  local -n list=$1
  local highlight=$2
  local -a marks=()
  if [[ -n ${3:-} ]]; then
    local -n marks_ref=$3
    marks=("${marks_ref[@]}")
  fi
  local row marker prefix
  for ((row = 0; row < ${#list[@]}; row++)); do
    marker="${C_DIM}[ ]${C_RESET}"
    if ((${#marks[@]} > 0)); then
      if ((marks[row])); then
        marker="${C_GREEN}[x]${C_RESET}"
      fi
    else
      marker=' '
    fi
    prefix=' '
    if ((row == highlight)); then
      prefix="${C_BOLD}${C_CYAN}❯${C_RESET}"
      printf ' %s %s %s%s%s\n' >&2 "${prefix}" "${marker}" "${C_BOLD}${C_CYAN}" "${list[row]}${C_RESET}"
    else
      printf ' %s %s %s\n' >&2 "${prefix}" "${marker}" "${list[row]}"
    fi
  done
}

# Print one canonical key name from raw input. Returns 4 when stdin closed,
# which callers treat as "leave the menu". Unknown keys print "none" so the
# caller simply redraws instead of aborting.
_menu_key() {
  local key
  IFS= read -rsn1 key || return 4
  if [[ ${key} == $'\x1b' ]]; then
    local rest=''
    if IFS= read -rsn2 -t 0.05 rest; then
      case ${rest} in
        '[A') echo up; return 0 ;;
        '[B') echo down; return 0 ;;
        *) echo none; return 0 ;;
      esac
    fi
    echo back
    return 0
  fi
  case ${key} in
    k) echo up ;;
    j) echo down ;;
    ' ') echo space ;;
    '') echo enter ;;
    q | Q) echo quit ;;
    a | A) echo all ;;
    r | R) echo reset ;;
    c | C) echo customize ;;
    b | B) echo back ;;
    *) echo none ;;
  esac
}

# Lines produced by one menu frame (blank + title + rows + blank + hint).
# Every redraw erases exactly this many lines so frames never drift.
_frame_height() {
  echo $(( $1 + 4 ))
}

# Erase the frame of a menu showing $1 rows. Called on every redraw and
# before every return; skipping it on a return is what makes nested menus
# (customize flows) stack stale copies in the terminal.
_menu_erase() {
  printf '\e[%dA\e[J' "$( _frame_height "$1" )" >&2
}

# Initial cursor row for a menu, from MENU_INIT_HIGHLIGHT if the caller set
# it, clamped into range; falls back to $2. Consumes the variable so it never
# leaks into an unrelated nested menu.
_menu_start_row() {
  local wanted=${MENU_INIT_HIGHLIGHT:-$2}
  unset MENU_INIT_HIGHLIGHT
  ((wanted >= 0 && wanted < $1)) && { echo "${wanted}"; return 0; }
  echo "${2}"
}

# Single select: menu_select_one title hint default_index option...
menu_select_one() {
  local title=$1 hint=$2 default=$3
  shift 3
  local -a rows=("$@")
  local highlight
  highlight="$(_menu_start_row ${#rows[@]} "${default}")"
  local key
  while true; do
    printf '\n%s\n' "${C_BOLD}${title}${C_RESET}" >&2
    _menu_render rows "${highlight}" ''
    printf '\n%s\n' "${C_DIM}${hint}${C_RESET}" >&2
    MENU_HIGHLIGHT=${highlight}
    key="$(_menu_key)" || menu_interrupted
    case ${key} in
      up) ((highlight = (highlight - 1 + ${#rows[@]}) % ${#rows[@]})) ;;
      down) ((highlight = (highlight + 1) % ${#rows[@]})) ;;
      enter)
        MENU_LAST_KEY=enter
        _menu_erase ${#rows[@]}
        echo "${highlight}"
        return 0
        ;;
      back | quit)
        if [[ ${MENU_ON_QUIT:-abort} == back ]]; then
          MENU_LAST_KEY=back
          _menu_erase ${#rows[@]}
          return 2
        fi
        menu_interrupted
        ;;
      none) : ;;
    esac
    _menu_erase ${#rows[@]}
  done
}

# Multi select: menu_select_many title hint checked_name required_name option...
# checked_name is the caller's 0/1 array, mutated in place as the user toggles.
# required_name is the caller's 0/1 array of rows that may not be unchecked;
# pass an empty string when every row is toggleable.
menu_select_many() {
  local title=$1 hint=$2 checked_name=$3 required_name=$4
  shift 4
  local -a rows=("$@")
  local -n marks=${checked_name}
  local -a required=()
  if [[ -n ${required_name} ]]; then
    local -n required_ref=${required_name}
    required=("${required_ref[@]}")
  fi
  local highlight key item count
  highlight="$(_menu_start_row ${#rows[@]} 0)"
  while true; do
    count=0
    for ((item = 0; item < ${#marks[@]}; item++)); do
      ((marks[item])) && count=$((count + 1))
    done
    printf '\n%s\n' "${C_BOLD}${title}${C_RESET}" >&2
    _menu_render rows "${highlight}" "${checked_name}"
    printf '\n%s %s%s%s\n' >&2 "${C_DIM}${hint}${C_RESET}" "${C_BOLD}" "${count}/${#rows[@]} selected" "${C_RESET}"
    MENU_HIGHLIGHT=${highlight}
    key="$(_menu_key)" || menu_interrupted
    case ${key} in
      up) ((highlight = (highlight - 1 + ${#rows[@]}) % ${#rows[@]})) ;;
      down) ((highlight = (highlight + 1) % ${#rows[@]})) ;;
      space)
        if [[ ${required[highlight]:-0} == 1 ]]; then
          :
        else
          ((marks[highlight] ^= 1))
        fi
        ;;
      all)
        local toggle=1
        ((marks[highlight])) && toggle=0
        for ((item = 0; item < ${#marks[@]}; item++)); do
          [[ ${required[item]:-0} == 1 ]] && continue
          marks[item]=${toggle}
        done
        ;;
      reset)
        for ((item = 0; item < ${#marks[@]}; item++)); do
          [[ ${required[item]:-0} == 1 ]] && continue
          marks[item]=1
        done
        ;;
      customize)
        MENU_LAST_KEY=customize
        _menu_erase ${#rows[@]}
        return 3
        ;;
      enter)
        MENU_LAST_KEY=enter
        _menu_erase ${#rows[@]}
        return 0
        ;;
      back | quit)
        if [[ ${MENU_ON_QUIT:-abort} == back ]]; then
          MENU_LAST_KEY=back
          _menu_erase ${#rows[@]}
          return 2
        fi
        menu_interrupted
        ;;
      none) : ;;
    esac
    _menu_erase ${#rows[@]}
  done
}
