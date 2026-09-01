#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

backup_root=''
backup_target() {
  local target=$1 relative
  if [[ -z ${backup_root} ]]; then
    backup_root="${HOME}/.config-backup/workstation-$(date +%Y%m%d-%H%M%S)"
    install -d "${backup_root}"
  fi
  relative=${target#"${HOME}/"}
  install -d "${backup_root}/$(dirname -- "${relative}")"
  mv -- "${target}" "${backup_root}/${relative}"
  log_warn "Backed up ${target} under ${backup_root}."
}

path_has_linked_parent() {
  local path=$1 current=${HOME} component relative
  relative=${path#"${HOME}/"}
  IFS='/' read -r -a parts <<< "$(dirname -- "${relative}")"
  for component in "${parts[@]}"; do
    [[ -n ${component} && ${component} != . ]] || continue
    current="${current}/${component}"
    [[ ! -L ${current} ]] || return 0
  done
  return 1
}

copy_tree() {
  local root=$1 source relative target
  while IFS= read -r -d '' source; do
    relative=${source#"${root}/"}
    target="${HOME}/${relative}"
    path_has_linked_parent "${target}" \
      && die "Refusing to deploy through a linked parent of ${target}."
    install -d "$(dirname -- "${target}")"
    if [[ -e ${target} || -L ${target} ]]; then
      if [[ -f ${target} && ! -L ${target} ]] && cmp -s "${source}" "${target}"; then
        continue
      fi
      backup_target "${target}"
    fi
    install --mode="$(stat -c %a "${source}")" "${source}" "${target}"
  done < <(find "${root}" -type f -print0 | sort -z)
}

log_step 'Copying managed configuration (never symlinking it)'
copy_tree "${DISTRO_ROOT}/dotfiles/desktop"
copy_tree "${DISTRO_ROOT}/dotfiles/agents"

xdg-user-dirs-update

if command -v noctalia >/dev/null 2>&1; then
  noctalia config validate "${HOME}/.config/noctalia/config.toml"
fi
if command -v Hyprland >/dev/null 2>&1; then
  Hyprland --verify-config --config "${HOME}/.config/hypr/hyprland.lua"
fi

log_success 'Hyprland, Noctalia, Ghostty, terminal, Thunar, GTK, agent instructions, and helper scripts are deployed.'
