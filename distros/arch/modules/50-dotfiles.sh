#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

backup_dir=''

create_backup_dir() {
  if [[ -z ${backup_dir} ]]; then
    install -d "${HOME}/.config-backup"
    backup_dir="$(mktemp -d "${HOME}/.config-backup/dotfiles-$(date +%Y%m%d-%H%M%S)-XXXXXX")"
  fi
}

backup_path() {
  local target=$1 relative backup_target
  relative=${target#"${HOME}/"}
  create_backup_dir
  backup_target="${backup_dir}/${relative}"
  install -d "$(dirname -- "${backup_target}")"

  if [[ -L ${target} ]]; then
    # Keep a usable snapshot rather than another link that could break when
    # its source repository is moved or deleted.
    if [[ -e ${target} ]]; then
      cp -aL -- "${target}" "${backup_target}"
      rm -f -- "${target}"
    else
      mv -- "${target}" "${backup_target}"
    fi
  else
    mv -- "${target}" "${backup_target}"
  fi
  log_warn "Backed up ${target} to ${backup_target}"
}

# Older revisions used Stow, which could make an entire config directory a
# symlink into this repository. Detach each such directory before writing so
# no deployed path can continue to resolve through the clone.
ensure_real_directory() {
  local directory=$1 temporary

  if [[ -L ${directory} ]]; then
    temporary="$(mktemp -d "${directory}.copy-XXXXXX")"
    if [[ -d ${directory} ]]; then
      cp -aL -- "${directory}/." "${temporary}/"
    fi
    rm -f -- "${directory}"
    mv -- "${temporary}" "${directory}"
    log_warn "Replaced linked directory ${directory} with a real copy."
  elif [[ -e ${directory} && ! -d ${directory} ]]; then
    backup_path "${directory}"
    install -d "${directory}"
  else
    install -d "${directory}"
  fi
}

ensure_real_parents() {
  local target=$1 relative component current
  local -a components=()
  relative=${target#"${HOME}/"}
  current=${HOME}
  IFS='/' read -r -a components <<< "$(dirname -- "${relative}")"

  for component in "${components[@]}"; do
    [[ -n ${component} && ${component} != '.' ]] || continue
    current="${current}/${component}"
    ensure_real_directory "${current}"
  done
}

log_step "Copying dotfiles into the home directory"

mapfile -d '' dotfile_sets < <(find "${DISTRO_ROOT}/dotfiles" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
[[ ${#dotfile_sets[@]} -gt 0 ]] || die "No dotfile sets found."

if find "${DISTRO_ROOT}/dotfiles" -mindepth 1 ! -type d ! -type f -print -quit | grep -q .; then
  die "The dotfiles source contains a symlink or unsupported file type; refusing to deploy links."
fi

for dotfile_set in "${dotfile_sets[@]}"; do
  while IFS= read -r -d '' source_dir; do
    relative=${source_dir#"${dotfile_set}/"}
    [[ ${relative} != "${source_dir}" ]] || continue
    ensure_real_parents "${HOME}/${relative}/placeholder"
    ensure_real_directory "${HOME}/${relative}"
  done < <(find "${dotfile_set}" -mindepth 1 -type d -print0 | sort -z)

  while IFS= read -r -d '' source_file; do
    relative=${source_file#"${dotfile_set}/"}
    target="${HOME}/${relative}"
    ensure_real_parents "${target}"

    if [[ -e ${target} || -L ${target} ]]; then
      if [[ ! -L ${target} && -f ${target} ]] && cmp -s -- "${source_file}" "${target}"; then
        continue
      fi
      backup_path "${target}"
    fi

    cp --preserve=mode,timestamps --remove-destination -- "${source_file}" "${target}"
  done < <(find "${dotfile_set}" -type f -print0 | sort -z)
done

if command -v xdg-user-dirs-update >/dev/null 2>&1; then
  xdg-user-dirs-update
fi

# hypr-vars.lua tells Caelestia's keybinding to launch helium-browser, so the
# xdg-open default must agree with it: everything that opens a link without a
# keybind -- Discord, Obsidian, VS Code -- reads mimeapps.list instead, and
# without this the "default browser" is whatever xdg-open happens to resolve
# first. The desktop entry is discovered rather than hardcoded: the AUR
# package's entry name is not stable enough to guess, and naming a missing
# entry would break xdg-open rather than fix it.
log_step "Registering the default browser"
if ! command -v xdg-settings >/dev/null 2>&1; then
  log_warn "xdg-settings is unavailable; the default browser was not registered. Run ./install.sh 10 first."
else
  helium_desktop_entry=''
  while IFS= read -r -d '' desktop_file; do
    grep -Eq '^MimeType=.*x-scheme-handler/https' "${desktop_file}" || continue
    grep -Eq '^Exec=(.*/)?helium' "${desktop_file}" || continue
    helium_desktop_entry="${desktop_file##*/}"
    break
  done < <(find /usr/share/applications "${XDG_DATA_HOME:-${HOME}/.local/share}/applications" \
    -maxdepth 1 -name '*.desktop' -print0 2>/dev/null | sort -z)

  if [[ -z ${helium_desktop_entry} ]]; then
    log_warn "No Helium desktop entry handling https was found; the default browser is unchanged. Run ./install.sh 25 to install helium-browser-bin."
  elif xdg-settings set default-web-browser "${helium_desktop_entry}"; then
    log_success "Default browser set to ${helium_desktop_entry}."
  else
    log_warn "xdg-settings rejected ${helium_desktop_entry}; the default browser is unchanged."
  fi
fi

# Caelestia themes terminals through its fish config, which replays the active
# scheme's escape sequences at every interactive start. A terminal that launches
# any other shell keeps its own default palette, so fish has to be the login
# shell for Ghostty to look like foot does.
log_step "Setting fish as the login shell"
install_user="$(id -un)"
fish_path="$(command -v fish)" || die "fish is not installed. Run ./install.sh 10 first."
if ! grep -Fxq "${fish_path}" /etc/shells; then
  die "${fish_path} is missing from /etc/shells; chsh would reject it."
fi
current_shell="$(getent passwd "${install_user}" | cut -d: -f7)"
if [[ ${current_shell} == "${fish_path}" ]]; then
  log_success "fish is already the login shell for ${install_user}."
else
  as_root chsh -s "${fish_path}" "${install_user}"
  log_warn "Changed the login shell from ${current_shell:-none} to ${fish_path}. It takes effect at the next login."
fi

hypr_main_config="${HOME}/.config/hypr/hyprland.lua"
if [[ -f ${hypr_main_config} ]]; then
  require_command Hyprland
  if ! verify_output="$(Hyprland --verify-config --config "${hypr_main_config}" 2>&1)"; then
    die "Hyprland rejected the final copied Caelestia configuration: ${verify_output//$'\n'/; }"
  fi
else
  die "Caelestia's Hyprland entry file is missing after dotfile deployment: ${hypr_main_config}. Run ./install.sh 45 first."
fi

log_success "Dotfiles copied. No configuration is linked to the repository."
log_success "The final Caelestia configuration passes Hyprland's verifier."
