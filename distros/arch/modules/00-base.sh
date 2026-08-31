#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

# Arch-specific pacman preparation, used only by this module.

enable_multilib() {
  local pacman_config=/etc/pacman.conf
  local pacman_backup=/etc/pacman.conf.workstation-backup

  require_command pacman-conf
  if pacman-conf --repo-list | grep -Fxq multilib; then
    return
  fi

  grep -Eq '^#\[multilib\]$' "${pacman_config}" \
    || die "The standard commented [multilib] section is missing from ${pacman_config}; enable multilib manually."

  log_step "Enabling Arch's multilib repository for Steam and 32-bit gaming libraries"
  if [[ ! -e ${pacman_backup} ]]; then
    as_root cp --archive -- "${pacman_config}" "${pacman_backup}"
  fi

  as_root sed -i \
    -e '/^#\[multilib\]$/,/^$/ s/^#\(\[multilib\]\)$/\1/' \
    -e '/^\[multilib\]$/,/^$/ s/^#\(Include = \/etc\/pacman.d\/mirrorlist\)$/\1/' \
    "${pacman_config}"

  pacman-conf --repo-list | grep -Fxq multilib \
    || die "Unable to enable multilib. Restore ${pacman_backup} and update ${pacman_config} manually."
}

configure_pacman_options() {
  local pacman_config=/etc/pacman.conf
  local pacman_backup=/etc/pacman.conf.workstation-backup
  local changed=false

  # Arch ships all of these commented out. ParallelDownloads is the one that
  # measurably changes install time; Color and VerbosePkgLists make what pacman
  # is about to do readable before it does it.
  local option
  for option in Color VerbosePkgLists; do
    if ! grep -Eq "^${option}\\b" "${pacman_config}" && grep -Eq "^#${option}\\b" "${pacman_config}"; then
      if [[ ! -e ${pacman_backup} ]]; then
        as_root cp --archive -- "${pacman_config}" "${pacman_backup}"
      fi
      as_root sed -i -E "s/^#(${option}\\b.*)$/\\1/" "${pacman_config}"
      changed=true
    fi
  done

  if ! grep -Eq '^ParallelDownloads[[:space:]]*=' "${pacman_config}" \
    && grep -Eq '^#ParallelDownloads[[:space:]]*=' "${pacman_config}"; then
    if [[ ! -e ${pacman_backup} ]]; then
      as_root cp --archive -- "${pacman_config}" "${pacman_backup}"
    fi
    as_root sed -i -E 's/^#(ParallelDownloads[[:space:]]*=.*)$/\1/' "${pacman_config}"
    changed=true
  fi

  # ILoveCandy is not present in the shipped file at all, so it is inserted
  # rather than uncommented. It only changes the progress bar.
  if ! grep -Eq '^ILoveCandy[[:space:]]*$' "${pacman_config}" && grep -Eq '^Color\b' "${pacman_config}"; then
    if [[ ! -e ${pacman_backup} ]]; then
      as_root cp --archive -- "${pacman_config}" "${pacman_backup}"
    fi
    as_root sed -i -E '0,/^Color\b.*$/s//&\nILoveCandy/' "${pacman_config}"
    changed=true
  fi

  if [[ ${changed} == true ]]; then
    log_step "Enabled pacman's colour, verbose package list and parallel download options"
    pacman-conf >/dev/null \
      || die "The edited ${pacman_config} is not parseable. Restore ${pacman_backup}."
  fi
}

enable_multilib
configure_pacman_options

log_step "Fully updating Arch Linux and installing build tools"
as_root pacman -Syu --needed --noconfirm base-devel git

if ! pacman -Q paru >/dev/null 2>&1; then
  paru_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/workstation-paru-XXXXXX")"
  log_step "Cloning the paru AUR build files"
  git clone --depth 1 https://aur.archlinux.org/paru.git "${paru_build_dir}/paru"

  log_warn "paru is itself an AUR package. Review its complete build instructions before approving it:"
  declare -a paru_review_files=("${paru_build_dir}/paru/PKGBUILD")
  while IFS= read -r -d '' paru_install_file; do
    paru_review_files+=("${paru_install_file}")
  done < <(find "${paru_build_dir}/paru" -maxdepth 1 -type f -name '*.install' -print0 | sort -z)
  for paru_review_file in "${paru_review_files[@]}"; do
    printf '\n--- %s ---\n' "${paru_review_file##*/}"
    sed -n '1,$p' "${paru_review_file}"
  done
  printf '\nBuild and install this paru package? [y/N] '
  read -r paru_answer < /dev/tty
  [[ ${paru_answer} == [Yy] || ${paru_answer} == [Yy][Ee][Ss] ]] \
    || die "paru installation declined; its build files remain in ${paru_build_dir}/paru for inspection."

  (
    cd "${paru_build_dir}/paru"
    makepkg --cleanbuild --syncdeps --install --needed
  )
fi

require_command paru
paru_path="$(command -v paru)"
paru_owner="$(pacman -Qqo "${paru_path}" 2>/dev/null || true)"
[[ ${paru_owner} == paru ]] \
  || die "The active paru executable (${paru_path}) is owned by '${paru_owner:-no package}', not the reviewed paru package."
paru --version >/dev/null \
  || die "The installed paru executable cannot start."

log_success "Base system ready."
