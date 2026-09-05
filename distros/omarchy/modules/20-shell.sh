#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

log_step 'Installing the shell package group'
install_pacman_manifest "${DISTRO_ROOT}/packages/shell.txt"

backup_root=''
backup_target() {
  local target=$1 relative
  if [[ -z ${backup_root} ]]; then
    backup_root="${HOME}/.config-backup/omarchy-$(date +%Y%m%d-%H%M%S)"
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

log_step 'Copying the managed fish configuration (never symlinking it)'
while IFS= read -r -d '' source_file; do
  relative=${source_file#"${DISTRO_ROOT}/dotfiles/fish/"}
  target="${HOME}/${relative}"
  path_has_linked_parent "${target}" \
    && die "Refusing to deploy the fish configuration through a linked parent of ${target}."
  install -d "$(dirname -- "${target}")"
  if [[ -e ${target} || -L ${target} ]]; then
    if [[ -f ${target} && ! -L ${target} ]] && cmp -s -- "${source_file}" "${target}"; then
      continue
    fi
    backup_target "${target}"
  fi
  install --mode="$(stat -c %a "${source_file}")" "${source_file}" "${target}"
done < <(find "${DISTRO_ROOT}/dotfiles/fish" -type f -print0 | sort -z)

log_success 'Fish configuration deployed. Omarchy already ships fish as the login shell.'
