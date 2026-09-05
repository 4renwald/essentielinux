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

log_step 'Copying dotfiles into the home directory'

mapfile -d '' dotfile_sets < <(find "${DISTRO_ROOT}/dotfiles" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
[[ ${#dotfile_sets[@]} -gt 0 ]] || die 'No dotfile sets found.'

if find "${DISTRO_ROOT}/dotfiles" -mindepth 1 ! -type d ! -type f -print -quit | grep -q .; then
  die 'The dotfiles source contains a symlink or unsupported file type; refusing to deploy links.'
fi

for dotfile_set in "${dotfile_sets[@]}"; do
  while IFS= read -r -d '' source_file; do
    relative=${source_file#"${dotfile_set}/"}
    target="${HOME}/${relative}"
    path_has_linked_parent "${target}" \
      && die "Refusing to deploy through a linked parent of ${target}."
    install -d "$(dirname -- "${target}")"
    if [[ -e ${target} || -L ${target} ]]; then
      if [[ -f ${target} && ! -L ${target} ]] && cmp -s -- "${source_file}" "${target}"; then
        continue
      fi
      backup_target "${target}"
    fi
    install --mode="$(stat -c %a "${source_file}")" "${source_file}" "${target}"
  done < <(find "${dotfile_set}" -type f -print0 | sort -z)
done

# Codex discovers a single global AGENTS.md and has no additive instruction
# mechanism, so the deployed privilege-escalation rules and the vendored
# Karpathy guidelines are combined here. ChatGPT desktop's Codex surface reads
# this same file.
log_step 'Assembling the Codex global instructions'
codex_agents="${HOME}/.codex/AGENTS.md"
codex_karpathy="${HOME}/.codex/instructions/karpathy-guidelines.md"
[[ -f ${codex_agents} && -f ${codex_karpathy} ]] \
  || die "Codex instruction sources missing after dotfile deployment: ${codex_agents}, ${codex_karpathy}"
{ cat -- "${codex_agents}"; printf '\n'; cat -- "${codex_karpathy}"; } > "${codex_agents}.tmp"
mv -- "${codex_agents}.tmp" "${codex_agents}"

log_success 'Fish configuration and agent skills deployed. Omarchy already ships fish as the login shell.'
