#!/usr/bin/env bash
set -Eeuo pipefail

readonly DISTRO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="$(cd -- "${DISTRO_ROOT}/../.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

require_command start-hyprland

readonly GREETER_HOME=/var/lib/greeter
readonly NIRI_GREETER_CONFIG=/etc/greetd/niri-greeter-config.kdl
readonly KITTY_GREETER_CONFIG=/etc/greetd/kitty.conf

# sysc-greet renders inside a compositor rather than on the VT, so the greeter
# needs niri to display in and kitty to run in. Both are Arch packages; the
# greeter itself is the AUR package installed from aur.txt by module 25.
log_step "Installing greetd and the sysc-greet display stack"
as_root pacman -S --needed --noconfirm greetd niri kitty

require_command niri
require_command kitty
command -v sysc-greet >/dev/null 2>&1 \
  || die "sysc-greet is not installed. It comes from aur.txt: run ./install.sh 25 first."

sysc_greet_path="$(command -v sysc-greet)"

# The AUR package and the upstream tarball disagree about where the binary
# lands (/usr/bin versus /usr/local/bin) while the shipped compositor config
# hardcodes one of them. Reconcile them rather than letting the greeter fail
# at boot with a blank screen.
for greeter_file in "${NIRI_GREETER_CONFIG}" "${KITTY_GREETER_CONFIG}"; do
  [[ -f ${greeter_file} ]] \
    || die "${greeter_file} is missing. It ships with the sysc-greet package; reinstall it with 'paru -S sysc-greet'."
done

referenced_path="$(grep -oE '(/usr(/local)?/bin/)sysc-greet' "${NIRI_GREETER_CONFIG}" | head -n1 || true)"
if [[ -z ${referenced_path} ]]; then
  die "${NIRI_GREETER_CONFIG} does not invoke sysc-greet by an absolute path; review it before continuing."
elif [[ ${referenced_path} != "${sysc_greet_path}" ]]; then
  log_warn "${NIRI_GREETER_CONFIG} runs ${referenced_path} but sysc-greet is installed at ${sysc_greet_path}."
  niri_config_backup="${NIRI_GREETER_CONFIG}.workstation-backup"
  [[ -e ${niri_config_backup} ]] || as_root cp --archive -- "${NIRI_GREETER_CONFIG}" "${niri_config_backup}"
  as_root sed -i "s|${referenced_path}|${sysc_greet_path}|g" "${NIRI_GREETER_CONFIG}"
  grep -Fq "${sysc_greet_path}" "${NIRI_GREETER_CONFIG}" \
    || die "Failed to correct the sysc-greet path in ${NIRI_GREETER_CONFIG}. Restore ${niri_config_backup}."
  log_success "Corrected the greeter's sysc-greet path to ${sysc_greet_path}."
fi

# greetd's own package creates the greeter user, but sysc-greet needs it to
# have this specific home and to sit in the video, render and input groups.
# The AUR package's scriptlet normally does this; verify rather than assume.
log_step "Preparing the greeter account"
if ! id greeter >/dev/null 2>&1; then
  as_root useradd -M -d "${GREETER_HOME}" -G video,render,input -s /usr/bin/nologin greeter
  log_success "Created the greeter user."
else
  current_greeter_home="$(getent passwd greeter | cut -d: -f6)"
  if [[ ${current_greeter_home} != "${GREETER_HOME}" ]]; then
    as_root usermod -d "${GREETER_HOME}" greeter
    log_warn "Moved the greeter home from ${current_greeter_home:-none} to ${GREETER_HOME}."
  fi
  for greeter_group in video render input; do
    if ! id -nG greeter | tr ' ' '\n' | grep -Fxq "${greeter_group}"; then
      as_root usermod -aG "${greeter_group}" greeter
      log_warn "Added the greeter user to the ${greeter_group} group."
    fi
  done
fi

as_root install -d -m0755 -o greeter -g greeter \
  "${GREETER_HOME}" \
  "${GREETER_HOME}/Pictures/wallpapers" \
  "${GREETER_HOME}/.cache" \
  "${GREETER_HOME}/.config" \
  "${GREETER_HOME}/.local/state" \
  /var/cache/sysc-greet

log_step "Deploying the greetd configuration"
if path_has_symlink /etc/greetd; then
  die "Refusing to deploy through a linked /etc/greetd directory. Replace it with a real directory first."
fi
as_root install -d -m0755 /etc/greetd
# Switching greeters is the one change here that can leave a machine with no
# way to log in graphically, so keep whatever configuration currently works.
greetd_config_backup=/etc/greetd/config.toml.workstation-backup
if [[ -f /etc/greetd/config.toml && ! -e ${greetd_config_backup} ]] \
  && ! cmp -s -- "${DISTRO_ROOT}/etc/greetd/config.toml" /etc/greetd/config.toml; then
  as_root cp --archive -- /etc/greetd/config.toml "${greetd_config_backup}"
  log_warn "Preserved the previous greetd configuration as ${greetd_config_backup}."
fi
as_root cp --remove-destination --preserve=mode,timestamps -- "${DISTRO_ROOT}/etc/greetd/config.toml" /etc/greetd/config.toml
as_root chmod 0644 /etc/greetd/config.toml
if path_has_symlink /etc/greetd/config.toml \
  || ! grep -Fq -- "niri -c ${NIRI_GREETER_CONFIG}" /etc/greetd/config.toml; then
  die "The copied greetd configuration is linked or does not start niri with the sysc-greet configuration."
fi

# sysc-greet offers shutdown and reboot from the login screen; without this
# rule polkit refuses them for the unprivileged greeter user. It ships with the
# package, so only warn if it is absent.
if [[ ! -f /etc/polkit-1/rules.d/85-greeter.rules ]]; then
  log_warn "/etc/polkit-1/rules.d/85-greeter.rules is missing; shutdown and reboot from the login screen will be denied."
fi

# Caelestia's execs.lua starts gnome-keyring-daemon, but starting the daemon
# does not unlock the login keyring: without PAM handing it the password that
# was just typed, every session begins with an unlock prompt, and applications
# that will not prompt (VS Code among them) fall back to storing secrets in
# plaintext. Both lines are `optional`, so a missing or failing module can
# never block authentication.
readonly GREETD_PAM=/etc/pam.d/greetd
readonly KEYRING_PAM_MODULE=/usr/lib/security/pam_gnome_keyring.so

if [[ ! -f ${KEYRING_PAM_MODULE} ]]; then
  log_warn "${KEYRING_PAM_MODULE} is missing; skipping keyring auto-unlock. Run ./install.sh 10 to install gnome-keyring."
elif [[ ! -f ${GREETD_PAM} ]]; then
  log_warn "${GREETD_PAM} does not exist; skipping keyring auto-unlock."
elif path_has_symlink "${GREETD_PAM}"; then
  die "Refusing to edit a linked PAM configuration: ${GREETD_PAM}"
elif grep -Eq '^[[:space:]]*(auth|session)[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so' "${GREETD_PAM}"; then
  log_success "greetd already unlocks the login keyring through PAM."
else
  log_step "Adding keyring auto-unlock to ${GREETD_PAM}"
  greetd_pam_backup="${GREETD_PAM}.workstation-backup"
  if [[ ! -e ${greetd_pam_backup} ]]; then
    as_root cp --archive -- "${GREETD_PAM}" "${greetd_pam_backup}"
    log_warn "Preserved the previous ${GREETD_PAM} as ${greetd_pam_backup}."
  fi
  printf '%s\n' \
    'auth       optional     pam_gnome_keyring.so' \
    'session    optional     pam_gnome_keyring.so auto_start' \
    | as_root tee -a "${GREETD_PAM}" >/dev/null
  grep -Eq '^[[:space:]]*session[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so[[:space:]]+auto_start' "${GREETD_PAM}" \
    || die "Failed to add the keyring lines to ${GREETD_PAM}. Restore ${greetd_pam_backup}."
fi

log_step "Enabling greetd"
dm_link=/etc/systemd/system/display-manager.service
if [[ -L ${dm_link} ]]; then
  current_dm="$(basename "$(readlink "${dm_link}")")"
  if [[ ${current_dm} != greetd.service ]]; then
    log_warn "Replacing the active display manager (${current_dm}) with greetd. Other desktops remain selectable in the sysc-greet session list."
    as_root systemctl disable "${current_dm}" >/dev/null 2>&1 || as_root rm -f "${dm_link}"
  fi
fi
as_root systemctl enable greetd.service

# greetd-tuigreet is what this repository used before sysc-greet. Leaving it
# installed is harmless, but it is no longer referenced by anything.
if pacman -Q greetd-tuigreet >/dev/null 2>&1; then
  log_warn "greetd-tuigreet is still installed and no longer used. Remove it with: sudo pacman -Rns greetd-tuigreet"
fi

log_success "greetd will start sysc-greet after the next reboot."
log_warn "Pick the Hyprland session in sysc-greet's session list; it reads /usr/share/wayland-sessions."
